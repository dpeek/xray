package xray;

import haxe.ds.GenericStack;
import haxe.macro.Expr;
import haxeparser.Data;
import xray.Data;

using haxe.macro.ExprTools;

class Processor
{
	var index:Int;
	var types:Array<TypeInfo>;
	var tokens:Array<Token>;
	var scopes:GenericStack<Map<String, Position>>;

	public function new(types:Array<TypeInfo>)
	{
		this.types = types;
	}

	public function getPosition(name:String)
	{
		var current = scopes.first();
		for (scope in scopes)
			if (scope.exists(name))
				return scope.get(name);
		return null;
	}

	public function process(tokens:Array<Token>, module:Module, moduleName:String)
	{
		this.scopes = new GenericStack();
		pushScope('module');

		this.index = 0;
		this.tokens = tokens;

		importModule('StdTypes');
		importModule(moduleName);
		if (moduleName.indexOf('.') > -1)
			importPackage(moduleName.substr(0, moduleName.lastIndexOf('.')));

		for (type in module.decls)
		{
			switch (type.decl)
			{
				case EImport(sl, mode):
				case EUsing(path):
				case EClass(d): processClass(d);
				case EEnum(d): processEnum(d);
				case EAbstract(d): processAbstract(d);
				case ETypedef(d): processTypedef(d);
			}
		}
	}

	function importModule(name:String)
	{
		trace('import $name');
		var file = name.split('.').join('/') + '.hx';
		for (type in types)
		{
			if (type.pos.file == file)
			{
				var name = type.name.split('.').pop();
				trace('set: $name');
				scopes.first().set(name, type.pos);
			}
		}
	}

	function importPackage(name:String)
	{
		trace('import $name');
		for (type in types)
		{
			if (type.name.indexOf('.') == -1) continue;
			var pack = type.name.substr(0, type.name.lastIndexOf('.'));
			if (pack == name)
			{
				var name = type.name.split('.').pop();
				trace('set: $name');
				scopes.first().set(name, type.pos);
			}
		}
	}

	function processClass(d:Definition<ClassFlag, Array<Field>>)
	{
		for (field in d.data) processField(field);
	}

	function processEnum(d:Definition<EnumFlag, Array<EnumConstructor>>)
	{

	}
	function processAbstract(d:Definition<AbstractFlag, Array<Field>>)
	{

	}
	function processTypedef(d:Definition<EnumFlag, ComplexType>)
	{

	}

	function processField(field:Field)
	{
		switch (field.kind)
		{
			case FVar(t, e):
			case FFun(f): processFunction(f, field.pos);
			case FProp(get, set, t, e):
		}
	}

	function processFunction(f:Function, pos:Position)
	{
		pushScope('function');
		for (arg in f.args)
			setScope(arg.name, pos);
		if (f.expr != null)
			processExpr(f.expr);
		popScope('function');
	}

	function findIdent(id:String, pos:Position)
	{
		return find(function (token) {
			if (token.pos.min < pos.min) return false;
			return switch (token.tok)
			{
				case Const(CIdent(s)) if (s == id): true;
				default: false;
			}
		});
	}

	function find(f:Token -> Bool)
	{
		while (index < tokens.length)
		{
			var token = tokens[index];
			if (f(token)) return token;
			index += 1;
		}
		return null;
		// throw 'token not found!';
	}

	function processExpr(expr:Expr)
	{
		// trace(expr.toString());
		switch (expr.expr)
		{
			case EConst(CIdent(s)):
				// trace(s);
			case EFor(it, expr):
				pushScope('for');
				processExpr(it);
				processExpr(expr);
				popScope('for');
			case EBlock(exprs):
				pushScope('block');
				for (expr in exprs) processExpr(expr);
				popScope('block');
			case EIn(e1, e2):
				setScope(e1.toString(), e1.pos);
				processExpr(e2);
			case EVars(vars):
				for (v in vars) setScope(v.name, expr.pos);
			case ESwitch(e, cases, edef):
				processExpr(e);
				for (c in cases)
				{
					pushScope('case');
					for (value in c.values) processCaseValue(value);
					if (c.guard != null) processExpr(c.guard);
					if (c.expr != null) processExpr(c.expr);
					popScope('case');
				}
				if (edef != null) processExpr(edef);
			default:
				expr.iter(processExpr);
		}
	}

	function processCaseValue(expr:Expr)
	{
		switch (expr.expr)
		{
			case ECall(e, params):
				for (param in params)
					setScope(param.toString(), param.pos);
			default:
		}
	}

	function pushScope(id:String)
	{
		trace('push $id');
		scopes.add(new Map<String, Position>());
	}

	function popScope(id:String)
	{
		trace('pop $id');
		scopes.pop();
	}

	function setScope(name:String, pos:Position)
	{
		trace('set: $name');
		var token = findIdent(name, pos);
		if (token == null) trace('could not find token for $name')
		else scopes.first().set(name, token.pos);
	}
}
