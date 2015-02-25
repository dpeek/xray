package xray;

import js.html.*;
import haxeparser.Data;
import xray.Data;

class Browser
{
	static var UI_PLATFORMS = ['js', 'flash', 'flash8'];
	static var SYS_PLATFORMS = ['cpp', 'cs', 'java', 'neko', 'python', 'php'];
	static var PLATFORMS = UI_PLATFORMS.concat(SYS_PLATFORMS);

	static function main()
	{
		new Browser();
	}

	var rangeMin:Int;
	var rangeMax:Int;
	var lastQuery:Float;
	var query:String = '';
	var types:Array<TypeInfo> = [];
	var platform = '';

	var platformSelect:SelectElement;
	var listElement:UListElement;
	var sourceElement:DivElement;
	var linesElement:PreElement;
	var codeElement:PreElement;

	var path:String;
	var source:String;
	var processor:Processor;

	function new()
	{
		var http = new haxe.Http('map.json');
		http.onData = onMapData;
		http.request();
	}

	function updateLocation()
	{
		var window = js.Browser.window;
		var hash = window.location.hash;
		var position = hash.substr(2);
		var file = position.split(':')[0];
		if (file == '') return;

		if (position.indexOf(':') > -1)
		{
			var range = position.split(':')[1].split('-').map(Std.parseInt);
			rangeMin = range[0];
			rangeMax = range[1];
		}
		else
		{
			rangeMin = rangeMax = 0;
		}

		var http = new haxe.Http('src/$file');
		trace('loading: $file');
		http.onData = function (source) onLoad(file, source);
		http.request();
	}

	function updatePlatform()
	{
		platform = platformSelect.value;
		parse();
		updateSearch();
	}

	function onMapData(data:String)
	{
		types = haxe.Json.parse(data);
		processor = new Processor(types);

		var body = js.Browser.document.body;

		var headerElement = js.Browser.document.createDivElement();
		body.appendChild(headerElement);

		headerElement.className = 'header';

		platformSelect = js.Browser.document.createSelectElement();
		headerElement.appendChild(platformSelect);

		for (platform in ['all'].concat(PLATFORMS))
		{
			var option = js.Browser.document.createOptionElement();
			option.value = platform;
			option.innerText = platform;
			platformSelect.appendChild(option);
		}

		sourceElement = js.Browser.document.createDivElement();
		body.appendChild(sourceElement);

		sourceElement.className = 'source';

		linesElement = js.Browser.document.createPreElement();
		sourceElement.appendChild(linesElement);

		linesElement.className = 'lines';

		codeElement = js.Browser.document.createPreElement();
		sourceElement.appendChild(codeElement);

		codeElement.className = 'code';

		codeElement.onmouseup = function (e:MouseEvent) {
			var element:SpanElement = cast e.target;
			if (element.className != "type") return;
			load(element.innerText, true);
		}

		listElement = js.Browser.document.createUListElement();
		body.appendChild(listElement);

		listElement.className = 'search';

		listElement.onmouseup = function (e:MouseEvent) {
			var element:UListElement = cast e.target;
			if (element.tagName == "SPAN") element = cast element.parentElement;
			load(element.innerText);
		}

		js.Browser.document.onkeypress = function (e:KeyboardEvent) {
			if (e.charCode == 8) query = '';
			filter(String.fromCharCode(e.which));
		}

		js.Browser.window.onhashchange = function (_) updateLocation();
		platformSelect.onchange = function (_) updatePlatform();

		updatePlatform();
		updateLocation();
	}

	function load(name:String, ?inFile:Bool=false)
	{
		// trace('load $name $inFile');
		var pos = null;
		if (inFile) pos = processor.getPosition(name);
		if (pos == null)
			for (type in types)
				if (type.name == name)
					pos = type.pos;
		if (pos != null)
			js.Browser.window.location.hash = '/' + pos.file + ':' + pos.min + '-' + pos.max;
	}

	function onLoad(path, source)
	{
		this.path = path;
		this.source = source;
		parse();
	}

	// comment
	function parse()
	{
		if (source == null) return;

		var input = byte.ByteData.ofString(source);
		var parser = new haxeparser.HaxeParser(input, path);

		var defines = getDefines();
		for (key in defines.keys())
			parser.define(key, defines.get(key));

		var module = parser.parse();
		var tokens = parser.source.tokens;

		var moduleName = path.split('/').join('.');
		moduleName = moduleName.substr(0, moduleName.length - 3);

		processor.process(tokens, module, moduleName);

		var state = [];
		var buf = new StringBuf();
		for (token in tokens)
		{
			var classes = token.classes;
			var space = token.space;

			if (classes.length == 0)
			{
				switch (token.tok)
				{
					case Kwd(KwdClass | KwdEnum | KwdTypedef | KwdAbstract
						| KwdPackage | KwdImport | KwdUsing | KwdFunction):
						classes.push('directive');
					case Kwd(KwdTrue | KwdFalse | KwdNull):
						classes.push('constant');
					case Kwd(_):
						classes.push('keyword');
					case Comment(_), CommentLine(_):
						classes.push('comment');
					case Const(CIdent(_)):
					case Const(CString(_)):
						classes.push('string');
					case Const(_):
						classes.push('constant');
					case Sharp(_):
						classes.push('macro');
					case Eof:
						buf.add(space);
						break;
					default:
				}
			}

			for (c in state)
				if (classes.indexOf(c) == -1)
					buf.add('</span>');
			buf.add(space);

			// if (rangeMax > rangeMin && token.pos.min == rangeMin)
			// 	buf.add('<span class="range">');

			for (c in classes)
				if (state.indexOf(c) == -1)
					buf.add('<span class="$c">');

			var tok = StringTools.htmlEscape(TokenDefPrinter.print(token.tok));
			buf.add(tok);

			// if (rangeMax > rangeMin && token.pos.max == rangeMax)
			// 	buf.add('</span>');

			state = classes;
		}

		for (c in state) buf.add('</span>');

		codeElement.innerHTML = buf.toString();

		var numLines = source.split('\n').length;
		var numWidth = Std.string(numLines).length;

		var linepos = null;
		if (rangeMax > rangeMin)
		{
			var position = new hxparse.Position(path, rangeMin, rangeMax);
			linepos = position.getLinePosition(input);
			sourceElement.scrollTop = (linepos.lineMin - 5) * 13;
		}
		var lines = new StringBuf();
		for (i in 1...numLines+1)
		{
			var line = StringTools.lpad(Std.string(i), '', numWidth);
			if (linepos != null && i >= linepos.lineMin && i <= linepos.lineMax)
			{
				lines.add('<span class="range">$line</span>\n');
			}
			else
			{
				lines.add('<span>$line</span>\n');
			}
		}

		linesElement.innerHTML = lines.toString();
	}

	function getDefines()
	{
		var defines = new Map<String, Dynamic>();
		defines.set(platform, true);
		defines.set('macro', true);
		if (isSys(platform)) defines.set('sys', true);
		return defines;
	}

	function isSys(platform:String)
	{
		return SYS_PLATFORMS.indexOf(platform) > -1;
	}

	function filter(char:String)
	{
		if (haxe.Timer.stamp() - lastQuery > 0.5) query = '';
		lastQuery = haxe.Timer.stamp();

		query += char;
		updateSearch();
	}

	function updateSearch()
	{
		var pat = ~/([^A-Z]*)([^.]*)(.*)/;
		if (!pat.match(query)) return;

		var packQuery = pat.matched(1).toLowerCase();
		var nameQuery = pat.matched(2).toLowerCase();
		var fieldQuery = pat.matched(3).toLowerCase();

		var types = types.filter(function (type) {
			if (platform == 'all') return true;
			var first = type.name.split('.')[0].toLowerCase();
			if (first == 'sys' && !isSys(platform)) return false;
			if (PLATFORMS.indexOf(first) > -1 && first != platform) return false;
			return true;
		}).map(function (type) {
			if (query == '') return {score:1.0, type:type};

			var parts = type.name.split('.');
			var name = parts.pop().toLowerCase();
			var pack = parts.join('.').toLowerCase();

			var score = 0.0;

			if (packQuery.length > 0)
			{
				if (pack.indexOf(packQuery) > -1) score +=1;
				if (pack.indexOf(packQuery) == 0) score +=1;
			}

			if (nameQuery.length > 0)
			{
				if (name.indexOf(nameQuery) > -1) score += 1 - ((name.length - nameQuery.length) / name.length);
				if (name == nameQuery) score += 1;
				if (name.indexOf(nameQuery) == 0) score += 1;
			}

			return {score:score, type:type};
		}).filter(function (result) {
			return result.score > 0;
		}).slice(0, 400);

		types.sort(function (a, b) {
			var diff = b.score - a.score;
			return diff > 0 ? 1 : diff < 0 ? -1 : 0;
		});

		listElement.innerHTML = types.map(function (result) {
			var name = result.type.name;

			name = new EReg(query, 'gi').map(name, function (e) {
				return '<span class="query">${e.matched(0)}</span>';
			});

			return '<li class="type">$name</li>';
		}).join('\n');
	}
}
