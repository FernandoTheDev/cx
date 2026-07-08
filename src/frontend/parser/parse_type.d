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
        TypeExpr t = new TypeExprPointer(base, base.pos is null ? pos : p.getPos(base.pos, pos));
        if (p.match(TokenKind.Star))
            return parsePointerType(t, pos);
        if (p.match(TokenKind.LBracket))
            return parseArrayType(t, pos);
        return t;
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
        return new TypeExprFunction(base, args, pos);
    }

    TypeExpr parseResultType(TypeExpr base, Position pos)
    {
        return new TypeExprResult(base, parse(), pos);
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
        if (p.match(TokenKind.Star))
            return parsePointerType(type, pos);
        if (p.match(TokenKind.Bang))
            return parseResultType(type, pos);
        if (p.match(TokenKind.LBracket))
            return parseArrayType(type, pos);
        if (t.kind != TokenKind.RBracket)
            p.consume(TokenKind.RBracket, "Expected ']'.");
        return type;
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
        if (p.match(TokenKind.Star))
            return parsePointerType(t, pos);
        return t;
    }

    TypeExpr parse()
    {
        TypeExpr primary = parsePrimary();
        
        if (p.match(TokenKind.Star))
            return parsePointerType(primary, p.previous().pos);

        if (p.match(TokenKind.LParen))
            return parseFunctionType(primary, p.previous().pos);

        if (p.match(TokenKind.Bang))
            return parseResultType(primary, p.previous().pos);

        if (p.match(TokenKind.LBracket))
            return parseArrayType(primary, p.previous().pos);

        if (p.match(TokenKind.LThan))
            return parseGenericType(primary, p.previous().pos);
        
        return primary;
    }
}
