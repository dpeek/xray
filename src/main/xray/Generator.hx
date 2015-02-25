package xray;

import haxe.io.Input;
import haxeparser.Data;
import haxeparser.HaxeParser;
import haxe.macro.Expr;
import xray.Data;

class Generator
{
	static function main()
	{
		var url = 'http://hxbuilds.s3-website-us-east-1.amazonaws.com/builds/haxe/mac/haxe_latest.tar.gz';
		new Generator().run(url);
	}

	var types:Array<TypeInfo>;

	function new() {}

	function run(url:String)
	{
		types = [];
		var input = load(url);
		process(input);
		types.sort(function (a, b) return Reflect.compare(a.name, b.name));
		var map = haxe.Json.stringify(types);
		sys.io.File.saveContent('www/map.json', map);
	}

	function process(input:Input)
	{
		var reader = new format.tgz.Reader(input);
		var start = haxe.Timer.stamp();
		var entries = reader.read();
		input.close();

		var first = entries.first();
		var std = '${first.fileName}std/';
		var stdLen = std.length;

		var start = haxe.Timer.stamp();
		for (entry in entries)
		{
			var fileName = entry.fileName;
			// only interested in std
			if (fileName.indexOf(std) < 0) continue;
			// ignore native _std
			if (fileName.indexOf('_std') > -1) continue;
			// truncate filename
			fileName = fileName.substr(stdLen);
			// ignore directories
			if (entry.fileSize == 0)
			{
				fileName = haxe.io.Path.removeTrailingSlashes(fileName);
				mkdir('www/src/$fileName');
				continue;
			}
			// ignore non-source files
			if (fileName.indexOf('.hx') < fileName.length - 3) continue;

			var source = entry.data.toString();
			var module = parse(fileName, source);
			for (decl in module.decls) processDecl(module, decl);

			// save output
			sys.io.File.saveContent('www/src/$fileName', source);
		}
		Sys.println('parsed in ${Std.int((haxe.Timer.stamp() - start) * 1000)}ms');
	}

	function mkdir(dir:String)
	{
		var parts = dir.split('/');
		for (i in 1...parts.length + 1)
		{
			var path = parts.slice(0, i).join('/');
			if (sys.FileSystem.exists(path)) continue;
			sys.FileSystem.createDirectory(path);
		}
	}

	function parse(path:String, source:String)
	{
		var start = haxe.Timer.stamp();
		var input = byte.ByteData.ofString(source);
		var module = null;
		hxparse.Utils.catchErrors(input, function() {
			var parser = new haxeparser.HaxeParser(input, path);
			try
			{
				module = parser.parse();
			}
			catch(e:haxeparser.HaxeParser.ParserError) {
				var pMsg = new hxparse.Position(e.pos.file, e.pos.min, e.pos.max).format(input);
				var ereg = ~/:(\d+):/;
				if (ereg.match(Std.string(pMsg)))
				{
					var lines = source.split('\n');
					source = lines[Std.parseInt(ereg.matched(1)) - 1];
				}
				throw '$pMsg: ${e.msg}\n\n$source';
			}
			catch (e:Dynamic)
			{
				var ereg = ~/:(\d+):/;
				if (ereg.match(Std.string(e)))
				{
					var lines = source.split('\n');
					Sys.println(lines[Std.parseInt(ereg.matched(1))]);
				}
				else
				{
					Sys.println(source);
				}
				throw e;
			}
		});
		return module;
	}

	function processDecl(module:Module, decl:TypeDecl)
	{
		switch (decl.decl)
		{
			case EClass(def): processDef(module, decl, def);
			case EEnum(def): processDef(module, decl, def);
			case EAbstract(def): processDef(module, decl, def);
			case ETypedef(def):
				var name = module.pack.concat([def.name]).join('.');
				var type = {name:name, pos:decl.pos};
				types.push(type);
			default:
		}
	}

	function processDef(module:Module, decl:TypeDecl, def:Definition<Dynamic, Array<{name:String, pos:Position}>>)
	{
		var name = module.pack.concat([def.name]).join('.');
		var type = {name:name, pos:decl.pos};
		types.push(type);
		Sys.println(name);
		// for (field in def.data)
		// {
		// 	type.fields.push({name:field.name, min:field.pos.min, max:field.pos.max});
		// 	Sys.println(name + '.' + field.name);
		// }
	}

	function load(url:String):Input
	{
		var name = haxe.io.Path.withoutDirectory(url);
		var cache = 'bin/$name';
		if (sys.FileSystem.exists(cache))
			return sys.io.File.read(cache);

		var data = haxe.Http.requestUrl(url);
		sys.io.File.saveContent(cache, data);
		return new haxe.io.BytesInput(haxe.io.Bytes.ofString(data));
	}
}
