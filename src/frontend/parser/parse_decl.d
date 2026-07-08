module frontend.parser.parse_decl;

import frontend;

import std.array : join, array;
import std.algorithm;
import std.format;
import std.stdio;

class ParseDecl
{
private:
    Parser p;

public:
    this(Parser p)
    {
        this.p = p;
    }

    Node parseVarDecl(TypeExpr texpr, Token name, bool consumeSemiColon = false)
    {
        // T NAME = VAL
        Node value;
        if (p.check(TokenKind.SemiColon))
            value = null;
        else
        {
            p.consume(TokenKind.Equals, "Expected '='.");
            value = p.parseExpr.parse();
        }
        
        if (consumeSemiColon)
            p.match(TokenKind.SemiColon);
        
        if (texpr is null || name is null || name.kind != TokenKind.Id)
        {
            // writeln("VAR: ", name);
            return new VarDecl("err", Node.init, false, new TypeExprNamed("/*err*/"), Position.init);
        }
        // writeln("Type: ", texpr);
        // writeln("Type Pos: ", texpr.pos);
        // writeln("Name: ", name.kind);
        // writeln("Name.s: ", name.s);
        // writeln("Value: ", value, "\n");
        p.vars[name.s] = texpr;
        // writeln("New Var: ", p.vars[name.s]);
        return new VarDecl(name.s, value, false, texpr, p.getPos(texpr.pos, name.pos));
    }

    Node parseFnDecl(TypeExpr retType, Token name, bool isStatic, string baseName = "")
    {
        TypeExpr[string] vars = p.vars;
        p.vars = (TypeExpr[string]).init;
        string fnName = (baseName != "" ? baseName ~ "_" : "") ~ name.s;
        p.consume(TokenKind.LParen, "Expected '('.");
        FnArg[] args;
        ubyte flags;

        while (!p.check(TokenKind.RParen))
        {
            TypeExpr type = p.parseType.parse();
            Token argName = p.consume(TokenKind.Id, "Expected an identifier.");
            Node val = null;
            if (p.match(TokenKind.Equals))
                val = p.parseExpr.parse();
            if (!p.check(TokenKind.RParen))
                p.consume(TokenKind.Comma, "Expected ','.");
            args ~= new FnArg(argName.s, type, val, argName.pos);
        }
        p.consume(TokenKind.RParen, "Expected ')'.");

        if (p.match(TokenKind.Overload))
        {
            string types = (args.map!(x => x.type_expr.toString()).array).join("_");
            fnName =  fnName ~ "_" ~ types;
            // writeln("fname: ", fnName);
            flags |= NodeFlags.Overload;
        }

        Node[] body;
        if (p.match(TokenKind.Arrow))
        {
            Node val = p.parseExpr.parse();
            body ~= new ReturnStmt(val, val.pos);
        }
        else
        {
            p.consume(TokenKind.LBrace, "Expected '{'.");
            while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
                body ~= p.parseIntern();
            p.consume(TokenKind.RBrace, "Expected '}'.");
        }

        if (isStatic)
        {
            flags |= NodeFlags.Static;
            p.ctx.statics[fnName] = true;   
        }

        p.vars = vars;
        return new FnDecl(fnName, args, body, retType, name.pos, flags);
    }

    Node parseStructDecl(Position pos)
    {
        string[] genericT;
        Token sname = p.consume(TokenKind.Id, "A name is expected for the struct.");
        if (p.match(TokenKind.LThan))
        {
            while (!p.isAtEnd() && !p.check(TokenKind.GThan))
            {
                genericT ~= p.consume(TokenKind.Id, "Expected an 'ID'.").s;
                if (!p.check(TokenKind.GThan))
                    p.consume(TokenKind.Comma, "Expected ','.");
            }
            p.consume(TokenKind.GThan, "Expected '>' after struct generic.");
        }
        p.consume(TokenKind.LBrace, "Expected '{'.");
        VarDecl[] fields;
        FnDecl[] functions;

        // registra os tipos temporariamente
        foreach (string T; genericT)
            p.types.set(T, new TypeExprNamed(T, Position.init));

        while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
        {
            bool isStatic = p.match(TokenKind.Static);
            TypeExpr type = p.parseType.parse();
            Token name = p.consume(TokenKind.Id, "Expected an 'ID'.");
            if (p.check(TokenKind.LParen))
            {
                functions ~= cast(FnDecl)parseFnDecl(type, name, isStatic, genericT.length > 0 ? "" : sname.s);
                // if (functions[$-1].flags & NodeFlags.Overload)
                //     functions[$-1].name = sname.s ~ "_" ~ functions[$-1].name;
            }
            else
                fields ~= cast(VarDecl)parseVarDecl(type, name, true);
        }

        foreach (string T; genericT)
            p.types.remove(T);

        Node node = new StructDecl(sname.s, fields, functions, genericT, p.getPos(pos, sname.pos));
        if (genericT.length > 0)
        {
            p.generic.set(sname.s, node);
            string nname = format("%s_%s", sname.s, genericT.join("_"));
            p.types.set(nname, new TypeExprUser(TypeExprKind.Struct, nname, pos));
        }

        p.consume(TokenKind.RBrace, "Expected '}'.");
        return node;
    }

    Node parseEnumDecl(Position pos)
    {
        Token sname = p.consume(TokenKind.Id, "A name is expected for the enum.");
        p.consume(TokenKind.LBrace, "Expected '{'.");
        string[] fields;
        
        while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
        {
            fields ~= p.consume(TokenKind.Id, "Expected an 'ID'.").s;
            p.match(TokenKind.Comma);
        }

        p.consume(TokenKind.RBrace, "Expected '}'.");
        return new EnumDecl(sname.s, fields, p.getPos(pos, sname.pos));
    }

    Node parseUnionDecl(Position pos)
    {
        Token sname = p.consume(TokenKind.Id, "A name is expected for the union.");
        p.consume(TokenKind.LBrace, "Expected '{'.");
        TypeExpr[string] fields;
        
        while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
        {
            // fields ~= p.consume(TokenKind.Id, "Esperado um 'ID'.").s;
            TypeExpr t = p.parseType.parse();
            fields[p.consume(TokenKind.Id, "Expected an 'ID'.").s] = t;
            p.match(TokenKind.SemiColon);
        }

        p.consume(TokenKind.RBrace, "Expected '}'.");
        return new UnionDecl(sname.s, fields, p.getPos(pos, sname.pos));
    }

    Node parseAliasDecl(Position pos)
    {
        string name = p.consume(TokenKind.Id, "Expected an 'ID'.").s;
        if (!p.check(TokenKind.Equals))
        {
            p.types.update(name, new TypeExprNamed(name, pos));
            return new AliasDecl(name, pos);    
        }
        p.consume(TokenKind.Equals, "Expected '='.");
        TypeExpr type = p.parseType.parse();
        p.types.update(name, type);
        return new AliasDecl(name, pos);
    }

    Node parse()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
        case TokenKind.Include:
            return new IncludeHeader(tk.s);

        case TokenKind.Struct:
            return this.parseStructDecl(tk.pos);

        case TokenKind.Enum:
            return this.parseEnumDecl(tk.pos);

        case TokenKind.Union:
            return this.parseUnionDecl(tk.pos);

        case TokenKind.Alias:
            return this.parseAliasDecl(tk.pos);

        default:
            return new IdentExpr("null", new TypeExprNamed("void", tk.pos), tk.pos);
        }
    }
}
