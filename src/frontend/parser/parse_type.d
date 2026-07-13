module frontend.parser.parse_type;

import frontend.parser;
import frontend.lexer;
import frontend;

import std.exception;
import std.conv;

class ParseType
{
private:
    Parser p;
    
public:
    this(Parser p)
    {
        this.p = p;
    }

    TypeExpr parsePrimary()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
            case TokenKind.Id:
                if (TypeExpr* t = p.types.get(tk.s))
                    return *t;
                return new TypeExprNamed(tk.s, tk.pos);
            default:
                p.err.error(tk.pos, "Invalid type.");
                return new TypeExprNamed("/*invalid type*/");
        }
    }

    TypeExpr parsePointerType(TypeExpr base, Position pos)
    {
        return checkAfter(new TypeExprPointer(base, base.pos is null ? pos : p.getPos(base.pos, pos)));
    }

    TypeExpr parseFunctionType(TypeExpr base, Position pos)
    {
        TypeExpr[] args;
        while (!p.isAtEnd() && !p.check(TokenKind.RParen))
        {
            args ~= parse();
            if (!p.check(TokenKind.RParen))
                p.consume(TokenKind.Comma, "Expected ','.");
        }
        p.consume(TokenKind.RParen, "Expected ')'.");
        return checkAfter(new TypeExprFunction(base, args, pos));
    }

    TypeExpr parseResultType(TypeExpr base, Position pos)
    {
        return checkAfter(new TypeExprResult(base, parse(), pos));
    }

    TypeExpr parseArrayType(TypeExpr base, Position pos)
    {
        // TODO: improve
        TypeExprArray type;
        Token t = p.advance();
        if (t.kind == TokenKind.RBracket)
            type = new TypeExprArray(base, "", pos);
        else if (t.kind == TokenKind.Id)
            type = new TypeExprArray(base, t.s, pos);
        else if (t.kind == TokenKind.UNumeric)
            type = new TypeExprArray(base, to!string(t.u), pos);
        else if (t.kind == TokenKind.Numeric)
            type = new TypeExprArray(base, to!string(t.l), pos);
        else
        {
            p.err.error(t.pos, "The array size is invalid.");
            type = new TypeExprArray(base, "", pos); // fallback pra não dar erro em comptime por segfault
        }
        if (t.kind != TokenKind.RBracket)
            p.consume(TokenKind.RBracket, "Expected ']'.");
        return checkAfter(type);
    }

    TypeExpr parseGenericType(TypeExpr name, Position pos)
    {
        TypeExpr[] args;
        while (!p.isAtEnd() && !p.check(TokenKind.GThan))
        {
            args ~= parse();
            if (!p.check(TokenKind.GThan))
                p.consume(TokenKind.Comma, "Expected ','.");
        }
        p.consume(TokenKind.GThan, "Expected '>'.");
        string n = name.toStr();
        p.generic.add(n, args);
        TypeExprGeneric t = new TypeExprGeneric(n, args, pos);
        return checkAfter(t);
    }

    TypeExpr checkAfter(TypeExpr type)
    {
        if (p.match(TokenKind.Star))
            return parsePointerType(type, type.pos);

        if (p.match(TokenKind.LParen))
            return parseFunctionType(type, type.pos);

        if (p.match(TokenKind.Bang))
            return parseResultType(type, type.pos);

        if (p.match(TokenKind.LBracket))
            return parseArrayType(type, type.pos);

        if (p.match(TokenKind.LThan))
            return parseGenericType(type, type.pos);

        if (p.match(TokenKind.Restrict))
            return new TypeExprRestrict(type, type.pos);

        return type;
    }

    TypeExpr parseInit()
    {
        // import std.stdio;
        // writeln(p.peek().s);

        if (p.match(TokenKind.Const))
            return new TypeExprConst(parseInit(), Position.init);

        if (p.match(TokenKind.Volatile))
            return new TypeExprVolatile(parseInit(), Position.init);

        if (p.match(TokenKind.Atomic))
            return new TypeExprAtomic(parseInit(), Position.init);

        if (p.match(TokenKind.Restrict))
            return new TypeExprRestrict(parseInit(), Position.init);

        return parsePrimary();
    }

    TypeExpr parse()
    {
        return checkAfter(parseInit());
    }
}
