package xray;

import haxeparser.Data;
import haxe.macro.Expr;

class RawTokenSource extends hxparse.LexerTokenSource<Token>
{
	public var tokens:Array<Token>;

	public function new(lexer, ruleset)
	{
		super(lexer, ruleset);
		tokens = [];
	}

	override public function token():Token
	{
		var token = lexer.token(ruleset);
		tokens.push(token);
		return token;
	}

	public function last(offset:Int=0)
	{
		return tokens[tokens.length - (offset + 1)];
	}

	public function classify(name:String, ?token:Token)
	{
		if (token == null) token = last(0);
		token.classes.push(name);
	}

	public function classifyRange(p1:Position, p2:Position, name:String)
	{
		for (i in 0...tokens.length)
		{
			var token = last(i);
			if (token.pos.min < p1.min) return;
			if (token.pos.min >= p1.min && token.pos.max <= p2.max) token.classes.push(name);
		}
	}
}
