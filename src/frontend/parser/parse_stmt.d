module frontend.parser.parse_stmt;

import frontend.parser;
import frontend.lexer;
import frontend;

import std.path : extension;
import std.stdio;

class ParseStmt
{
private:
    Parser p;

public:
    this(Parser p)
    {
        this.p = p;
    }

    Node[] parseBody()
    {
        Node[] body;
        if (p.match(TokenKind.LBrace))
        {
            while (!p.check(TokenKind.RBrace))
                body ~= p.parseIntern();
            p.consume(TokenKind.RBrace, "Expected '}'.");
        }
        else
            body ~= p.parseIntern();
        return
        body;
    }

    Node parseIfStmt(Position pos, bool isElse = false)
    {
        IfStmt _else = null;
        Node expr = isElse ? null : p.parseExpr.parse();

        // cobre casos de else if
        if (p.match(TokenKind.If))
            expr = p.parseExpr.parse();

        Node[] body = parseBody();

        if (!p.isAtEnd() && p.check(TokenKind.Else))
            _else = cast(IfStmt) parseIfStmt(p.advance().pos, true);

        return new IfStmt(expr, body, _else, pos);
    }

    Node parseReturnStmt(Position pos)
    {
        Node val = p.check(TokenKind.SemiColon) ? null : p.parseExpr.parse();
        return new ReturnStmt(val, pos);
    }

    Node parseDeferStmt(Position pos)
    {
        return new DeferStmt(p.parseExpr.parse(), pos);
    }

    Node parseWhileStmt(Position pos)
    {
        Node expr = p.parseExpr.parse();
        Node[] body = parseBody();
        return new WhileStmt(expr, body, pos);
    }

    Node parseForStmt(Position pos)
    {
        Node first, middle, end;
        p.consume(TokenKind.LParen, "Expected '('.");

        if (!p.check(TokenKind.SemiColon))
        {
            TypeExpr t = p.parseType.parse();
            Token name = p.consume(TokenKind.Id, "Expected 'ID'.");
            first = p.parseDecl.parseVarDecl(t, name);
        }

        p.consume(TokenKind.SemiColon, "Expected ';'.");
        if (!p.check(TokenKind.SemiColon))
            middle = p.parseExpr.parse();

        p.consume(TokenKind.SemiColon, "Expected ';'.");
        if (!p.check(TokenKind.RParen))
            end = p.parseExpr.parse();

        p.consume(TokenKind.RParen, "Expected ')'.");

        Node[] body = parseBody();
        return new ForStmt(first, middle, end, body, pos);
    }

    Node parseLabelStmt(Token name)
    {
        Node[] body;
        while (!p.isAtEnd() && (!p.check(TokenKind.RBrace)))
            body ~= p.parseIntern();
        // writeln(body);
        return new LabelStmt(name.s, body, name.pos);
    }

    Node parseGotoStmt(Position pos)
    {
        string name = p.consume(TokenKind.Id, "Expected an 'ID'.").s;
        return new GotoStmt(name, pos);
    }

    Node parseImportStmt(Position pos)
    {
        Node dir = p.parseExpr.parse();
        if (dir.kind != NodeKind.IdentExpr && dir.kind != NodeKind.MemberExpr && dir.kind != NodeKind
            .StringLit)
        {
            p.err.error(dir.pos, "The previous directory is invalid.");
            return dir;
        }
        string d = resolveDir(dir);
        if (d.length == 0)
            p.err.error(dir.pos, "The import directory cannot be null.");
        
        if (extension(d) != ".cx" && extension(d) != "")
            p.err.error(dir.pos, "The imported file is not a valid '.cx' file.");

        ImportStmt stmt = new ImportStmt(d, p.getPos(pos, dir.pos));
        Program prog = new Program([stmt]);
        new ImportResolver(p.ctx, prog, p.err, p.types, p.generic).resolve();
        p.imports ~= prog.body;
        return stmt;
    }

    string resolveDir(Node node)
    {
        if (node.kind == NodeKind.IdentExpr)
            return (cast(IdentExpr) node).val;
        if (node.kind == NodeKind.StringLit)
            return (cast(StringLit) node).val;
        if (node.kind == NodeKind.MemberExpr)
        {
            MemberExpr m = cast(MemberExpr) node;
            return resolveDir(m.left) ~ "/" ~ resolveDir(m.right);
        }
        p.err.error(node.pos, "Invalid value passed for directory resolution.");
        return "";
    }

    Node parse()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
        case TokenKind.Defer:
            return parseDeferStmt(tk.pos);

        case TokenKind.Return:
            return parseReturnStmt(tk.pos);

        case TokenKind.If:
            return parseIfStmt(tk.pos);

        case TokenKind.While:
            return parseWhileStmt(tk.pos);

        case TokenKind.For:
            return parseForStmt(tk.pos);

        case TokenKind.Break:
        case TokenKind.Continue:
            return new ContinueOrBreakStmt(tk.kind == TokenKind.Break, tk.pos);

        case TokenKind.Goto:
            return parseGotoStmt(tk.pos);

        case TokenKind.Import:
            return parseImportStmt(tk.pos);

        default:
            return new IdentExpr("null", new TypeExprNamed("void", tk.pos), tk.pos);
        }
    }
}
