module frontend.parser.parse_expr;

import frontend.parser;
import frontend.lexer;
import frontend;

import std.exception;
import std.stdio;
import std.conv;

enum Precedence : ubyte
{
    Low,
    Assign, // = += -= etc
    Or, // ||
    And, // &&
    BitOr, // |
    BitXor, // ^
    BitAnd, // &
    Eq, // == != ===
    Cmp, // < > <= >=
    Shift, // << >>
    Plus, // + -
    Mul, // * / %
    Unary, // ! ~ - * &
    Call, // () [] .
    High,
}

class ParseExpr
{
private:
    Parser p;

public:
    this(Parser p)
    {
        this.p = p;
    }

    Node nud()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
        case TokenKind.String:
            return new StringLit(tk.s, tk.pos);

        case TokenKind.Id:
            TypeExpr* t = p.types.get(tk.s);
            if (t && (
                    p.peek().kind == TokenKind.Id
                    || p.peek().kind == TokenKind.Star
                    || p.peek().kind == TokenKind.LParen
                    || p.peek().kind == TokenKind.LThan
                    || p.peek().kind == TokenKind.LBracket
                    || p.peek().kind == TokenKind.Bang
                ))
            {
                p.previous2(); // volta o advance feito
                TypeExpr type = p.parseType.parse();
                if (p.match(TokenKind.Dot))
                    return parseMemberExpr(new IdentExpr(type.toStr(), type, type.pos));
                Token name = p.consume(TokenKind.Id, "Expected an 'ID' after the type.");
                if (p.check(TokenKind.LParen))
                    return p.parseDecl.parseFnDecl(type, name, false);
                return p.parseDecl.parseVarDecl(type, name);
            }
            if (p.match(TokenKind.Colon))
                return p.parseStmt.parseLabelStmt(tk);
            TypeExpr type = null;
            if (tk.s in p.vars)
                type = p.vars[tk.s];
            if (type is null)
                type = new TypeExprNamed(tk.s, tk.pos);
            return new IdentExpr(tk.s, t is null ? type : *t, tk.pos);

        case TokenKind.Numeric:
        case TokenKind.UNumeric:
            bool isLong = tk.kind == TokenKind.Numeric;
            NumericLit node = new NumericLit(isLong, isLong ? tk.l : 0L, tk.pos);
            if (!isLong)
                node.u = tk.u;
            return node;

        case TokenKind.Double:
            return new DoubleLit(tk.d, tk.pos);

        case TokenKind.Float:
            return new FloatLit(tk.f, tk.pos);

        case TokenKind.Char:
            return new CharLit(to!char(tk.s), tk.pos);

        case TokenKind.Null:
            return new NullLit(tk.pos);

        case TokenKind.True:
        case TokenKind.False:
            return new BoolLit(tk.kind == TokenKind.True, tk.pos);

        case TokenKind.PPlus: // ++x
        case TokenKind.Plus: // +x
        case TokenKind.MMinus: // --x
        case TokenKind.Minus: // -x
        case TokenKind.BITNot: // ~x
        case TokenKind.Bang: // !x
        case TokenKind.BITAnd: // &x
        case TokenKind.Star: // *x
            Node val = parse(getPrecedence(tk.kind));
            return new UnaryExpr(val, tk.kind, p.getPos(tk.pos, val.pos), false);

        case TokenKind.LBrace:
            return parseStructLit(tk.pos);

        case TokenKind.LBracket:
            return parseArrayLit(tk.pos);

        case TokenKind.SizeOf:
            p.consume(TokenKind.LParen, "Expected '('.");
            TypeExpr expr = p.parseType.parse();
            Position end = p.consume(TokenKind.RParen, "Expected ')'.").pos;
            return new SizeOfExpr(expr, p.getPos(tk.pos, end));

        case TokenKind.LParen:
            return parseCastOrNode(tk.pos);

        default:
            p.err.error(tk.pos, "An expression is expected.");
            return new IdentExpr("null", new TypeExprNamed("void", tk.pos), tk.pos);
        }
    }

    Node parseArrayLit(Position pos)
    {
        Node[] values;
        while (!p.isAtEnd() && !p.check(TokenKind.RBracket))
        {
            values ~= parse();
            if (!p.check(TokenKind.RBracket))
                p.consume(TokenKind.Comma, "Expected ',' after the value.");
        }
        p.consume(TokenKind.RBracket, "Expected '}'.");
        return new ArrayLit(values, p.getPos(pos, p.previous().pos));
    }

    Node parseStructLit(Position pos)
    {
        Node[] values;
        while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
        {
            values ~= parse();
            if (!p.check(TokenKind.RBrace))
                p.consume(TokenKind.Comma, "Expected ',' after the value.");
        }
        p.consume(TokenKind.RBrace, "Expected '}'.");
        return new StructLit(values, p.getPos(pos, p.previous().pos));
    }

    Node parseCastOrNode(Position pos)
    {
        if (p.check(TokenKind.Id))
        {
            if (
                p.future(TokenKind.Star, 1) 
                || p.future(TokenKind.RParen, 1)
                || p.future(TokenKind.LThan, 1)
                || p.future(TokenKind.LBracket, 1)
                )
                if (p.types.exists(p.peek().s))
                {
                    TypeExpr to = p.parseType.parse();
                    p.consume(TokenKind.RParen, "Expected ')'.");
                    Node val = parse();
                    return new CastExpr(val, to, p.getPos(pos, val.pos));
                }
        }
        Node val = parse();
        p.consume(TokenKind.RParen, "Expected ')'.");
        return new GroupExpr(val, val.pos);
    }

    Node parseBinaryExprAssignStmt(bool isBinaryExpr, TokenKind op, Node left)
    {
        Node right = parse(getPrecedence(op));
        // writeln(op);
        // writeln(left.pos);
        // writeln(right);
        if (isBinaryExpr)
            return new BinaryExpr(left, right, op, p.getPos(left.pos, right.pos));
        // writeln(left);
        // writeln(right);
        // writeln(left.pos);
        // writeln(right.pos);
        // left.print(0);
        return new AssignStmt(left, right, op, p.getPos(left.pos, right.pos));
    }

    Node parseCallExpr(Node left)
    {
        Node[] args;
        while (!p.check(TokenKind.RParen))
        {
            args ~= parse();
            if (!p.check(TokenKind.RParen))
                p.consume(TokenKind.Comma, "Expected ','.");
        }
        p.consume(TokenKind.RParen, "Expected ')'.");
        return new CallExpr(left, args, left.pos);
    }

    Node parseMemberExpr(Node left)
    {
        Node val = parse(Precedence.Call);
        if (val.kind == NodeKind.IdentExpr && p.check(TokenKind.LParen))
        {
            p.advance(); // consome '('
            val = parseCallExpr(val); // reusa a função existente, empacota como CallExpr(val, args)
        }
        return new MemberExpr(left, val, p.getPos(left.pos, val.pos));
    }

    Node parseIndexExpr(Node left)
    {
        Node idx = parse();
        Position end = p.consume(TokenKind.RBracket, "Expected ']'.").pos;
        return new IndexExpr(left, idx, p.getPos(left.pos, end));
    }

    Node led(Node left)
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
        case TokenKind.Plus:
        case TokenKind.Minus:
        case TokenKind.Star:
        case TokenKind.Slash:
        case TokenKind.Modulo:
        case TokenKind.LThan:
        case TokenKind.GThan:
        case TokenKind.EEquals:
        case TokenKind.EEEquals:
        case TokenKind.NEquals:
        case TokenKind.LEquals:
        case TokenKind.GEquals:
        case TokenKind.BITAnd:
        case TokenKind.BITOr:
        case TokenKind.BITXor:
        case TokenKind.BITLeft:
        case TokenKind.BITRight:
        case TokenKind.And:
        case TokenKind.Or:
            return parseBinaryExprAssignStmt(true, tk.kind, left);
        case TokenKind.LParen:
            return parseCallExpr(left);
        case TokenKind.Dot:
            return parseMemberExpr(left);
        case TokenKind.Equals:
        case TokenKind.PLUSEquals:
        case TokenKind.MINUSEquals:
        case TokenKind.DIVEquals:
        case TokenKind.STAREquals:
        case TokenKind.MODEquals:
        case TokenKind.OBWEquals:
        case TokenKind.EBWEquals:
        case TokenKind.SHLEquals:
        case TokenKind.SHREquals:
            return parseBinaryExprAssignStmt(false, tk.kind, left);
        case TokenKind.LBracket:
            return parseIndexExpr(left);
        case TokenKind.PPlus:
        case TokenKind.MMinus:
            return new UnaryExpr(left, tk.kind, tk.pos, true);
        default:
            return left;
        }
    }

    Precedence getPrecedence(TokenKind kind)
    {
        switch (kind)
        {
        case TokenKind.Equals:
        case TokenKind.PLUSEquals:
        case TokenKind.MINUSEquals:
        case TokenKind.DIVEquals:
        case TokenKind.STAREquals:
        case TokenKind.MODEquals:
        case TokenKind.OBWEquals:
        case TokenKind.EBWEquals:
        case TokenKind.SHLEquals:
        case TokenKind.SHREquals:
            return Precedence.Assign;
        case TokenKind.Or:
            return Precedence.Or;
        case TokenKind.And:
            return Precedence.And;
        case TokenKind.BITOr:
            return Precedence.BitOr;
        case TokenKind.BITXor:
            return Precedence.BitXor;
        case TokenKind.BITAnd:
            return Precedence.BitAnd;
        case TokenKind.EEquals:
        case TokenKind.EEEquals:
        case TokenKind.NEquals:
            return Precedence.Eq;
        case TokenKind.LThan:
        case TokenKind.GThan:
        case TokenKind.LEquals:
        case TokenKind.GEquals:
            return Precedence.Cmp;
        case TokenKind.BITLeft:
        case TokenKind.BITRight:
            return Precedence.Shift;
        case TokenKind.Plus:
        case TokenKind.Minus:
            return Precedence.Plus;
        case TokenKind.Star:
        case TokenKind.Slash:
        case TokenKind.Modulo:
            return Precedence.Mul;
        case TokenKind.Dot:
        case TokenKind.LParen:
        case TokenKind.LBracket:
        case TokenKind.PPlus:
        case TokenKind.MMinus:
            return Precedence.Call;
        default:
            return Precedence.Low;
        }
    }

    Node parse(Precedence pre = Precedence.Low)
    {
        Node left = nud();
        while (!p.isAtEnd() && pre < getPrecedence(p.peek().kind))
            left = led(left);
        return left;
    }
}
