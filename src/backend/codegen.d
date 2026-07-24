module backend.codegen;

import backend.cx_builtins;
import frontend;
import utils;

import std.array : join, array;
import std.algorithm;
import std.format;
import std.stdio;
import std.conv;

final class CodeGen
{
private:
    Program program;
    TypeRegistry types;
    TypeResolver resolver;

    TypeExpr actualType;
    TypeExpr fnType;

    bool haveStackTrace, checkNullPtr;

    bool isFnStatic;
    bool genHeaderFile;
    string headerFile;
    ImportResolverContext* context;
    bool onLabel, deferOnLabel;

    bool[string] errorUnions;
    bool fnErrorUnion; // diz se a função atual retorna uma errorUnion
    string fnUnion; // a estrutura da função
    TypeExpr[2] fnError = [TypeExpr.init, TypeExpr.init]; // 0 pro OK | 1 pro ERRO
    uint tmp;
    bool[string] includes;
    bool[string] fnStatics;

    string[] defer;
    string[] header = [];
    string[] cxHeader = [];
    string[] typedefs;
    string[] data;
    string[] unionErrors;
    string[] protos;
    string[] source;

    string indent(string target, uint ind)
    {
        string c;
        for (uint i; i < ind; i++)
            c ~= " ";
        return c ~ target;
    }

    void emit(string code, uint ind)
    {
        if (code == "")
            return;
        source ~= indent(code, ind);
    }

    string[2] compileProgram()
    {
        foreach (ref node; program.body)
            compile(node, 0);

        string code, userCode;
        if (genHeaderFile)
        {
            import std.string : toUpper;
            string name = toUpper(headerFile[0..$-2]);
            code ~= format("#ifndef %s_CX_H\n", name);
            code ~= format("#define %s_CX_H\n\n", name);
        }
        code ~= header.join("\n");
        if (cxHeader.length > 0)
        {
            code ~= "\n\n/* CX Header */\n";
            code ~= cxHeader.join("\n");
        }
        if (typedefs.length > 0)
        {
            code ~= "\n\n/* Typedefs */\n";
            code ~= typedefs.join("\n");
        }
        if (data.length > 0)
        {
            code ~= "\n\n/* Data */\n";
            code ~= data.join("\n");
        }
        if (unionErrors.length > 0)
        {
            code ~= "\n\n/* Union Errors */\n";
            code ~= unionErrors.join("\n");
        }
        if (protos.length > 0)
        {
            code ~= "\n\n/* Prototypes */\n";
            code ~= protos.join("\n");
        }
        if (genHeaderFile)
            code ~= "\n\n#endif\n";

        if (genHeaderFile)
            userCode ~= format("#include \"%s\"", headerFile);
        else
        {
            userCode ~= code;
            code = [];
        }

        userCode ~= "\n\n/* Code */\n";
        userCode ~= source.join("\n");

        return [userCode, code];
    }

    void checkNullPtrFn(string val, Position pos)
    {
        if (checkNullPtr)
            emit(format(`%s(%s, %d, "%s");`, CXCheckNullPtr, val, pos.start.line, pos.filename), 4);
    }

    void compile(Node node, uint ind)
    {
        if (node is null)
        {
            emit("/* decl is null */", ind);
            return;
        }

        switch (node.kind)
        {
        case NodeKind.FnDecl:
            return compileFnDecl(as!FnDecl(node), ind);

        case NodeKind.IncludeHeader:
            string c = (cast(IncludeHeader) node).code;
            if (c in includes)
                return;
            includes[c] = true;
            header ~= "#" ~ c;
            return;

        case NodeKind.StructDecl:
            compileStructDecl(as!StructDecl(node), ind);
            return;

        case NodeKind.EnumDecl:
            return compileEnumDecl(as!EnumDecl(node), ind);

        case NodeKind.UnionDecl:
            compileUnionDecl(as!UnionDecl(node), ind);
            return;

        case NodeKind.AliasDecl:
        case NodeKind.ImportStmt:
            return;

        case NodeKind.RawStmt:
            RawStmt n = cast(RawStmt) node;
            return emit(indent("/* raw block */", ind) ~ n.code, 0);

        case NodeKind.VarDecl:
            data ~= compileVarDecl(cast(VarDecl)node, 0);
            return;

        default:
            emit("/* invalid decl */", ind);
            return;
        }
    }

    string compileUnionDecl(UnionDecl node, uint ind, bool anon = false)
    {
        string name = node.name;
        if (!anon)
            typedefs ~= format("typedef union %s %s;", name, name);
        string _data = format("union %s\n{\n", anon ? "" : name);
        foreach (string field, TypeExpr type; node.fields)
            _data ~= indent(format("%s %s;\n", type.toString(), field), ind + 4);
        _data ~= format("} %s;\n", anon ? name : "");
        if (!anon)
            data ~= _data;
        return _data;
    }

    void compileEnumDecl(EnumDecl node, uint ind)
    {
        string name = node.name;
        string _data = format("enum %s\n{\n", name);
        /*
        const char* ArrayError_ids[] = {
            [ArrayError_NotFound] = "NotFound"
        };
        */
        string ids = format("const char* %s_ids[] = {\n", name);
        foreach (string field; node.fields)
        {
            string namem = format("%s_%s", name, field);
            _data ~= indent(namem ~ ",\n", ind + 4);
            ids ~= indent(format("[%s] = \"%s\",\n", namem, field), 4);
        }
        ids ~= "};\n";
        _data ~= "};\n";
        data ~= _data;
        data ~= format("typedef enum %s %s;", name, name);
        data ~= ids;
    }

    string compileStmt(Node node, uint ind)
    {
        if (node is null)
            return indent("/* stmt is null */", ind);

        switch (node.kind)
        {
        case NodeKind.VarDecl:
            return compileVarDecl(as!VarDecl(node), ind);

        case NodeKind.ReturnStmt:
            return compileRetStmt(as!ReturnStmt(node), ind);

        case NodeKind.CallExpr:
            return compileCallStmt(as!CallExpr(node), ind);

        case NodeKind.AssignStmt:
            return indent(compileExpr(node) ~ ";", ind);

        case NodeKind.MemberExpr:
            return compileMemberStmt(as!MemberExpr(node), ind);

        case NodeKind.DeferStmt:
            DeferStmt def = cast(DeferStmt) node;
            defer ~= compileExpr(def.val) ~ ";";
            return indent("/* there was a defer here, it has already been resolved */", ind);

        case NodeKind.IfStmt:
            return compileIfStmt(as!IfStmt(node), ind);

        case NodeKind.WhileStmt:
            WhileStmt w = cast(WhileStmt) node;
            emit(format("while (%s)", compileExpr(w.expr)), ind);
            emitBody(w.body, ind);
            return "";

        case NodeKind.UnaryExpr:
            return indent(compileExpr(node) ~ ";", ind);

        case NodeKind.ForStmt:
            ForStmt f = cast(ForStmt) node;
            string first = f.first is null ? ";" : compileVarDecl(as!VarDecl(f.first), 0);
            string middle = f.middle is null ? "" : compileExpr(f.middle);
            string end = f.end is null ? "" : compileExpr(f.end);
            emit(format("for (%s %s; %s)", first, middle, end), ind);
            emitBody(f.body, ind);
            return "";

        case NodeKind.ContinueOrBreakStmt:
            ContinueOrBreakStmt n = cast(ContinueOrBreakStmt) node;
            return indent((n.isBreak ? "break" : "continue") ~ ";", ind);

        case NodeKind.GotoStmt:
            GotoStmt n = cast(GotoStmt) node;
            return indent(format("goto %s;", compileExpr(n.label)), ind);

        case NodeKind.LabelStmt:
            LabelStmt n = cast(LabelStmt) node;
            deferOnLabel = false;
            bool on = onLabel;
            onLabel = true;
            emit(format("%s:", n.name), ind);
            foreach (Node _; n.body)
                emit(compileStmt(_, ind), ind);
            onLabel = on;
            return "";

        case NodeKind.RawStmt:
            RawStmt n = cast(RawStmt) node;
            return indent("/* raw block */", ind) ~ n.code;

        case NodeKind.CaseStmt:
            CaseStmt c = cast(CaseStmt) node;
            emit(format("%s:", c.value is null ? "default" : format("case %s", compileExpr(c.value))), ind);
            if (c.hasVar)
                emit("{", ind);
            bool haveBraces;
            foreach (Node n; c.body)
            {
                if (n.kind == NodeKind.VarDecl)
                    haveBraces = true;
                emit(compileStmt(n, ind), ind-4);
            }
            if (c.hasVar)
                emit("}", ind);
            return "";
        
        case NodeKind.SwitchStmt:
            SwitchStmt s = cast(SwitchStmt) node;
            emit(format("switch(%s)", compileExpr(s.expr)), ind);
            emit("{", ind);
            foreach (CaseStmt c; s.cases)
                emit(compileStmt(cast(Node) c, ind + 4), ind);
            emit("}", ind);
            return "";

        case NodeKind.ForEachStmt:
            ForEachStmt fe = cast(ForEachStmt) node;
            
            string sname = fe.value.type_expr.toStr();
            string value = compileExpr(fe.value);

            FnDecl iter = resolver.findMethod(sname, "iter");
            string iterator = iter.type_expr.toString();
            
            string temp = format("__it%d", tmp++);
            string it = format("%s %s = %s_iter(&%s);", iterator, temp, sname, value);

            bool isRef = fe.v.kind == NodeKind.UnaryExpr;
            string val = isRef ? compileExpr((cast(UnaryExpr) fe.v).val) : compileExpr(fe.v);

            // writeln(sname);
            // writeln(value);
            // writeln(iterator);
            // writeln(temp);
            // writeln(it);
            
            emit(it, ind);
            emit(format("for (;%s.offset < %s.length; %s.offset++)", temp, temp, temp), ind);
            emit(format("{"), ind);
            if (fe.k !is null)
                emit(format("size_t %s = %s.offset;", compileExpr(fe.k), temp), ind+4);
            emit(format("__typeof__(%s(%s.ptr)) %s = %s(%s.ptr[%s.offset]);", 
               isRef ? "" : "*", temp, val, isRef ? "&" : "", temp, temp), ind+4);
            foreach (Node n; fe.body)
                emit(compileStmt(n, ind), ind);
            emit(format("}"), ind);
            
            // Iterator<int> __it1 = arr.iter(); OK
            // for (; __it1.offset < __it1.length; __it1.offset++) {
            //     int n = __it1.ptr[__it1.offset];
            //     num += n;
            // }

            return "";

        default:
            return indent("/* invalid stmt */", ind);
        }
    }

    string getOp(TokenKind k)
    {
        switch (k)
        {
        case TokenKind.PPlus:
            return "++";
        case TokenKind.MMinus:
            return "--";
        case TokenKind.Plus:
            return "+";
        case TokenKind.Minus:
            return "-";
        case TokenKind.Star:
            return "*";
        case TokenKind.Slash:
            return "/";
        case TokenKind.Modulo:
            return "%";
        case TokenKind.BITAnd:
            return "&";
        case TokenKind.BITNot:
            return "~";
        case TokenKind.BITOr:
            return "|";
        case TokenKind.BITLeft:
            return "<<";
        case TokenKind.BITRight:
            return ">>";
        case TokenKind.And:
            return "&&";
        case TokenKind.Or:
            return "||";
        case TokenKind.LThan:
            return "<";
        case TokenKind.GThan:
            return ">";
        case TokenKind.LEquals:
            return "<=";
        case TokenKind.GEquals:
            return ">=";
        case TokenKind.EEquals:
        case TokenKind.EEEquals:
            return "==";
        case TokenKind.NEquals:
            return "!=";
        case TokenKind.Equals:
            return "=";
        case TokenKind.PLUSEquals:
            return "+=";
        case TokenKind.MINUSEquals:
            return "-=";
        case TokenKind.DIVEquals:
            return "/=";
        case TokenKind.STAREquals:
            return "*=";
        case TokenKind.MODEquals:
            return "%=";
        case TokenKind.OBWEquals:
            return "|=";
        case TokenKind.EBWEquals:
            return "&=";
        case TokenKind.SHLEquals:
            return "<<=";
        case TokenKind.SHREquals:
            return ">>=";
        case TokenKind.Bang:
            return "!";
        case TokenKind.BITXor:
            return "^";
        default:
            return "/* unknown operator */";
        }
    }

    string escapeChar(char c)
    {
        switch (c)
        {
        case '\0': return "\\0";
        case '\n': return "\\n";
        case '\t': return "\\t";
        case '\r': return "\\r";
        case '\'': return "\\'";
        case '\\': return "\\\\";
        case '\a': return "\\a";
        case '\b': return "\\b";
        case '\f': return "\\f";
        case '\v': return "\\v";
        default:
            return format("%c", c);
        }
    }

    string escapeString(string s)
    {
        string buff;
        foreach (c; s) buff ~= escapeChar(c);
        return buff;
    }

    string compileExpr(Node node)
    {
        switch (node.kind)
        {
        case NodeKind.NumericLit:
            NumericLit num = cast(NumericLit) node;
            if (num.isLong)
                return to!string(num.l);
            return to!string(num.u);

        case NodeKind.FloatLit:
            return to!string((cast(FloatLit) node).val);

        case NodeKind.DoubleLit:
            return to!string((cast(DoubleLit) node).val);

        case NodeKind.BinaryExpr:
            BinaryExpr binary = cast(BinaryExpr) node;
            string left = compileExpr(binary.left);
            string right = compileExpr(binary.right);
            if (isPtr(binary.left.type_expr))  checkNullPtrFn(left, binary.left.pos);
            if (isPtr(binary.right.type_expr)) checkNullPtrFn(right, binary.right.pos);
            if (binary.op == TokenKind.EEEquals)
            {
                if (isString(binary.left.type_expr) && isString(binary.right.type_expr))
                    return format("strcmp(%s, %s) == 0", left, right);
                if (isStruct(binary.left.type_expr))
                {
                    string name = binary.left.type_expr.toStr();
                    FnDecl fn = resolver.findMethod(name, "cmp");
                    if (fn)
                        return format("%s_cmp(&%s, %s)", name, left, right);
                }
            }
            return format("%s %s %s", left, getOp(binary.op), right);

        case NodeKind.UnaryExpr:
            UnaryExpr un = cast(UnaryExpr) node;
            string op = getOp(un.op);
            string val = compileExpr(un.val);
            if (op == "*") checkNullPtrFn(val, un.pos);
            return format("%s%s", un.post ? val : op, un.post ? op : val);

        case NodeKind.StringLit:
            return format("\"%s\"", (cast(StringLit) node).val);

        case NodeKind.CharLit:
            return format("'%s'", escapeChar((cast(CharLit) node).val));

        case NodeKind.NullLit:
            return "NULL";

        case NodeKind.BoolLit:
            return (cast(BoolLit) node).val ? "true" : "false";

        case NodeKind.IdentExpr:
            return (cast(IdentExpr) node).val;

        case NodeKind.CallExpr:
            return compileCallExpr(as!CallExpr(node));

        case NodeKind.MemberExpr:
            return compileMemberExpr(as!MemberExpr(node));

        case NodeKind.AssignStmt:
            AssignStmt ass = cast(AssignStmt) node;
            return format("%s %s %s", compileExpr(ass.left), getOp(ass.op), compileExpr(ass.right));

        case NodeKind.StructLit:
            StructLit strc = cast(StructLit) node;
            bool haveComptimeArray;
            string[] values;
            
            for (ulong i; i < strc.values.length; i++)
            {
                Node n = strc.values[i];
                if (n.type_expr !is null && n.type_expr.kind == TypeExprKind.Array)
                    haveComptimeArray = true;
                values ~= compileExpr(n);
                if (n.kind == NodeKind.AssignStmt)
                    values[$-1] = "." ~ values[$-1];
            }

            TypeExpr type = strc.type_expr is null ? null : strc.type_expr;
            string def = format("{%s}", values.join(", "));

            if (!haveComptimeArray)
                return def;

            if (haveComptimeArray && type is null)
                return def;
            
            StructDecl decl = cast(StructDecl) context.symbols[type.toString()];
            
            if (decl is null)
                return def;

            string temp = format("temp_%d", tmp++);
            emit(format("%s;", type.toStrVar(temp)), 4);

            foreach (size_t i, VarDecl field; decl.fields)
            {
                string member = format("%s.%s", temp, field.name);
                if (field.type_expr !is null && field.type_expr.kind != TypeExprKind.Array)
                    emit(format("%s = %s;", member, values[i]), 4);
                else {
                    // writeln("COMPTIME");
                    string value;
                    if (
                        strc.values[i].kind == NodeKind.IdentExpr
                        || strc.values[i].kind == NodeKind.MemberExpr
                        || strc.values[i].kind == NodeKind.IndexExpr
                    )
                        value = values[i];
                    else {
                        // cria uma variavel temporaria
                        string tempField = format("temp_%d", tmp++);
                        emit(format("%s = %s;", field.type_expr.toStrVar(tempField), values[i]), 4);
                        value = tempField;
                    }
                    emit(format("memcpy(%s, %s, sizeof(%s));", member, value, member), 4);
                    // memcpy(temp_0.bar, name, sizeof(temp_0.bar));
                    // writeln(field.name);
                    // writeln(field.type_expr);
                }
            }

            // writeln(decl.fields);
            // writeln(haveComptimeArray, " ", values);
            return format("%s", temp);

        case NodeKind.ArrayLit:
            ArrayLit arr = cast(ArrayLit) node;
            string values;
            for (ulong i; i < arr.values.length; i++)
            {
                values ~= compileExpr(arr.values[i]);
                if ((i + 1) < arr.values.length)
                    values ~= ", ";
            }
            return format("{%s}", values);

        case NodeKind.CastExpr:
            CastExpr n = cast(CastExpr) node;
            return format("(%s)%s", n.type_expr.toString(), compileExpr(n.expr));

        case NodeKind.IndexExpr:
            IndexExpr idxExpr = cast(IndexExpr) node;
            string val = compileExpr(idxExpr.value);
            checkNullPtrFn(val, idxExpr.pos);
            // writeln(idxExpr.idx);
            // writeln(idxExpr.value);
            // writeln("val: ", val);
            if (RangeExpr range = cast(RangeExpr) idxExpr.idx)
            {
                string left = compileExpr(range.left);
                string right = compileExpr(range.right);

                if (range.left.kind == NodeKind.UnaryExpr)
                    left = right ~ left;

                return format("Slice_%s_%s(%s, %s, %s)", 
                    idxExpr.value.type_expr.toStr(), range.isCopy ? "copyOf" : "of",
                    val, left, right);
            }
            return format("%s[%s]", val, compileExpr(idxExpr.idx));

        case NodeKind.GroupExpr:
            return "(" ~ compileExpr((cast(GroupExpr) node).val) ~ ")";

        case NodeKind.SizeOfExpr:
            SizeOfExpr sz = cast(SizeOfExpr) node;
            return format("sizeof(%s)", sz.type_expr.toString());

        case NodeKind.TypeNameExpr:
            TypeNameExpr tn = cast(TypeNameExpr) node;
            return compileExpr(new StringLit(tn.expr.type_expr.toStr(), tn.pos));

        case NodeKind.TTypeExpr:
            TTypeExpr tn = cast(TTypeExpr) node;
            return compileExpr(new StringLit(tn.type.toStr(), tn.pos));

        case NodeKind.IsExpr:
            IsExpr tn = cast(IsExpr) node;
            // writeln("left: ", tn.left.toStr());
            // writeln("right: ", tn.right.toStr());
            return format("%s", tn.left.toStr() == tn.right.toStr() ? "true" : "false");

        case NodeKind.TernaryExpr:
            TernaryExpr tn = cast(TernaryExpr) node;
            return format("%s ? %s : %s", compileExpr(tn.expr), compileExpr(tn.left), compileExpr(tn.right));

        default:
            return "/* invalid expr */";
        }
    }

    void emitBody(Node[] body, uint ind)
    {
        // bool cond = body.length > 1 || defer.length > 0 || body.length == 0;
        // if (cond)
            emit("{", ind);
        foreach (Node node; body)
            emit(compileStmt(node, ind), ind);
        // if (cond)
            emit("}", ind);
    }

    string compileIfStmt(IfStmt node, uint ind)
    {
        string code = format("if (%s)", node.expr !is null ? compileExpr(node.expr) : "");
        if (!node.isElse)
        {
            emit(code, ind);
            emitBody(node.body, ind);
        }
        else
        {
            emit(format("else %s", node.expr !is null ? code : ""), ind);
            emitBody(node.body, ind);
        }
        if (node._else !is null)
            compileIfStmt(node._else, ind);
        return "";
    }

    string compileMemberStmt(MemberExpr node, uint ind)
    {
        return indent(format("%s;", compileMemberExpr(node)), ind);
    }

    string compileMemberExpr(MemberExpr node)
    {
        if (node.right.kind == NodeKind.StructLit)
        {
            // string expr = compileExpr(node.right);
            // writeln(expr);
            // return expr;
            return compileExpr(node.right);
        }

        TypeExpr type = node.left.type_expr;
        string typeName, id;
        bool isArrow;

        if (isResult(type) && node.right.kind == NodeKind.IdentExpr)
        {
            string val = (cast(IdentExpr) node.right).val;
            string expr = compileExpr(node.left);
            if (val == "ok" || val == "error")
                return format("%s.val.%s", expr, val);
        }

        IdentExpr idcast = cast(IdentExpr) node.right;
        string rval = idcast ? idcast.val : "";

        if (isString(type) && idcast)
            if (rval == "length")
                return format("strlen(%s)", compileExpr(node.left));

        if (isEnum(type) && idcast)
            if (rval == "id")
                return format("%s_ids[%s]", type.toStr(), compileExpr(node.left));

        if (type is null)
            isArrow = true;
        else if (type.kind == TypeExprKind.Pointer)
            isArrow = true;
        else if (type.kind == TypeExprKind.Struct)
            isArrow = false;

        if (type !is null)
            typeName = type.toStr();

        if (node.right.kind == NodeKind.CallExpr)
        {
            bool isStatic, fromSelf;
            if (node.left.kind == NodeKind.IdentExpr)
                id = (cast(IdentExpr) node.left).val;
            else if (MemberExpr m = cast(MemberExpr) node.left)
            {
                // LValue?
                string member = compileMemberExpr(m);
                if ((
                    m.left.kind == NodeKind.IdentExpr 
                    || m.left.kind == NodeKind.IndexExpr
                    || m.left.kind == NodeKind.MemberExpr)
                    && member[$-1] != ')'
                )
                    id = member;
                else
                {
                    id = format("tmp_%d", tmp++);
                    emit(format("%s %s = %s;", m.right.type_expr, id, member), 4);
                }
            } 
            else if (CallExpr c = cast(CallExpr) node.left)
            {
                id = format("tmp_%d", tmp++);
                emit(format("%s %s = %s;", c.type_expr, id, compileExpr(c)), 4);
            }

            if (id != "")
            {
                isStatic = types.exists(id);
                Node callee = (cast(CallExpr) node.right).callee;
                
                if (IdentExpr ide = cast(IdentExpr) callee)
                {
                    if (!isStatic)
                    isStatic = (ide.val in fnStatics) !is null;
                    // writeln(fnStatics, " ", ide.val, " ", isStatic);
                }
                
                if (node.left.type_expr.kind == TypeExprKind.Pointer)
                    fromSelf = true;

                if (id == "self")
                {
                    fromSelf = true;
                    if (actualType !is null)
                    {
                        type = actualType;
                        typeName = type.toStr();
                    }
                }
            }
            return format("%s", compileCallExpr(as!CallExpr(node.right), !isStatic,
                    format("%s%s", fromSelf ? "" : "&", id), typeName));
        }

        string symbol = isArrow ? "->" : ".";
        string left = compileExpr(node.left);
        if (isPtr(node.left.type_expr))
            checkNullPtrFn(left, node.left.pos);

        if (type !is null)
            if (type.kind == TypeExprKind.Enum || (type.kind == TypeExprKind.Struct && types.exists(left)))
                symbol = "_";

        return format("%s%s%s", left, symbol, compileExpr(node.right));
    }

    string compileCallExpr(CallExpr node, bool fromMethod = false, string var = "", string typeName = "", 
        bool isStmt = false)
    {
        string args = fromMethod ? var : "";
        if (node.args.length > 0 && fromMethod)
            args ~= ", ";
        for (ulong i; i < node.args.length; i++)
        {
            Node arg = node.args[i];
            string val = compileExpr(arg);
            args ~= val;
            // writeln(val, " ", node.type_expr, " ", node.pos.toString());
            if (isPtr(node.type_expr))  checkNullPtrFn(val, node.pos);
            if ((i + 1) < node.args.length)
                args ~= ", ";
        }
        string callee = compileExpr(node.callee);
        // writeln("Callee 1: ", callee);
        if (callee !in context.symbols)
        {
            // verifica se é overload
            string overload = (typeName == "" ? "" : typeName ~ "_") ~ callee ~ "_" ~
                (node.args.map!(n => n.type_expr is null ? "null" : n.type_expr.toString()).array).join("_");
            // writeln("Callee: ", overload);
            // writeln(context.symbols);
            if (overload in context.symbols)
                callee = overload;
            else
                callee = typeName == "" ? callee : typeName ~ "_" ~ callee;
            // else
                // writefln("Compiler warning: The function '%s' was not found.", callee);
        } else
            callee = typeName == "" ? callee : typeName ~ "_" ~ callee;
        string call = format("%s(%s)", clearNameMangling(callee), args);
        
        // special case
        if (callee == CXPanic)
            return format(`%s(%s, "%s", %d)`, CXPanic, args, node.pos.filename, node.pos.start.line);
        
        return haveStackTrace ? format(`%s("%s", %s, %d, "%s")`, 
            isStmt ? CXCallVoid : CXCall, callee, call, 
                node.pos.start.line, node.pos.filename) : call;
    }

    string compileCallStmt(CallExpr node, uint ind)
    {
        return indent(format("%s;", compileCallExpr(node, false, "", "", true)), ind);
    }

    string compileRetStmt(ReturnStmt node, uint ind)
    {
        deferResolve(ind);
        string val = node.val is null ? "" : compileExpr(node.val);
        if (fnErrorUnion)
        {
            if (node.val is null)
            {
                writeln("Error: The function cannot return void.");
                return "return 0;";
            }
            // writeln(node.val);
            // writeln(node.val.pos.toString());
            // writeln(node.val.type_expr);
            if (node.val.type_expr !is null)
                if (node.val.type_expr.toString() == fnUnion)
                    return indent(format("return %s;", val), ind);
            // writeln(fnError[0]);
            // writeln(fnError[1], "\n");
            bool ok;
            if (node.val.type_expr is null) // fallback
                ok = true;
            else
                ok = node.val.type_expr.toString() != fnError[1].toString();
            // writeln(ok);
            val = format("(%s) { .valid = %s, .val.%s = %s }",
                fnUnion, ok ? "true" : "false", ok ? "ok" : "error", val);
        }
        return indent(format("return %s%s;", (val == "self" && !isFnStatic && fnType.kind != TypeExprKind.Pointer) 
            && fnType !is null ? "*" : "", val), ind);
    }

    string compileVarDecl(VarDecl node, uint ind)
    {
        if (node.val is null)
            return indent(format("%s;", node.type_expr.toStrVar(node.name)), ind);
        return indent(format("%s = %s;", node.type_expr.toStrVar(node.name), compileExpr(node.val)), ind);
    }

    void compileStructDecl(StructDecl node, uint ind)
    {
        string name = node.name;
        if (node.genericT.length > 0 || types.get(name) is null) 
            return;
        TypeExpr t = *types.get(name);
        TypeExpr a = actualType;
        actualType = t;
        typedefs ~= format("typedef struct %s %s;", name, name);
        string _data = format("struct %s {\n", name);
        // emit(format("struct %s {", name), ind);
        foreach (VarDecl var; node.fields)
            _data ~= compileVarDecl(var, ind + 4) ~ "\n";
        foreach (UnionDecl un; node.unions)
            _data ~= compileUnionDecl(un, ind, true);
        _data ~= "};\n";
        data ~= _data;
        foreach (FnDecl fn; node.functions)
            compileFnDecl(fn, ind, true, name, node.fromGeneric);
        actualType = a;
    }

    void compileFnDecl(FnDecl fn, uint ind, bool isMethod = false, string methodType = "", bool fromGeneric = false)
    {
        defer = []; // limpa
        fnType = fn.type_expr;
        string args;
        isFnStatic = !!(fn.flags & NodeFlags.Static);
        bool hasSelf = !isFnStatic;
        if (isMethod && hasSelf)
            args ~= format("%s* self", methodType);
        if (fn.args.length > 0 && isMethod && hasSelf)
            args ~= ", ";
        for (ulong i; i < fn.args.length; i++)
        {
            FnArg arg = fn.args[i];
            args ~= format("%s", arg.type_expr.toStrVar(arg.name));
            if ((i + 1) < fn.args.length)
                args ~= ", ";
        }
        if (!fromGeneric)
            methodType = "";
        if (args.length == 0) args = "void";
        bool cond = fn.type_expr.kind == TypeExprKind.Function;
        string name = cond ? format("%s(%s)", fn.name, args) : fn.name;
        name = clearNameMangling(name);
        
        // writeln("FUNC NAME: ", name);
        string proto = format("%s%s", 
                /* proto */ 
                fn.type_expr.toStrVar(isMethod 
                ? format("%s%s", (methodType == "" ? "" : methodType ~ "_"), name)
                : name),
                /* args */ 
                cond ? "" : format("(%s)", args));

        protos ~= proto ~ ";";
        emit(proto, ind);
        emit("{", ind);
        proto ~= " {\n";
        bool error = fnErrorUnion;
        fnErrorUnion = fn.type_expr.kind == TypeExprKind.Result;
        if (fnErrorUnion)
        {
            TypeExprResult res = cast(TypeExprResult) fn.type_expr;
            fnUnion = clearNameMangling(res.toString());
            fnError[0] = res.ok;
            fnError[1] = res.error;

            if (fnUnion !in errorUnions)
            {
                // adiciona no data para gerar depois, assim como o typedef
                errorUnions[fnUnion] = true;
                typedefs ~= format("typedef struct %s %s;", fnUnion, fnUnion);
                unionErrors ~= format("struct %s { bool valid; union { %s ok; %s error; } val; };", fnUnion,
                    res.ok.toString(), res.error.toStr());
            }
        }
        bool hasReturn;
        foreach (Node node; fn.body)
        {
            emit(compileStmt(node, ind + 4), ind);
            if (node.kind == NodeKind.ReturnStmt)
            {
                hasReturn = true;
                break;
            }
        }
        if (!hasReturn && !deferOnLabel)
            deferResolve(ind+4);
        fnErrorUnion = error;
        emit("}\n", ind);
    }

    void deferResolve(uint ind)
    {
        if (defer.length == 0)
            return;
        if (onLabel)
            deferOnLabel = true;
        // comportamento LIFO
        foreach_reverse (string def; defer)
            emit(def, ind);
    }

    bool isString(TypeExpr type)
    {
        TypeExprNamed t;
        if (TypeExprPointer p = cast(TypeExprPointer) type)
            t = cast(TypeExprNamed) p.base;
        else if (TypeExprArray a = cast(TypeExprArray) type)
            t = cast(TypeExprNamed) a.base;
        return t is null ? false : t.name == "char";
    }

    bool isResult(TypeExpr type)
    {
        if (TypeExprFunction f = cast(TypeExprFunction) type)
            return isResult(f.ret);
        if (type is null)
            return false;
        return type.kind == TypeExprKind.Result;
    }

    bool isEnum(TypeExpr type)
    {
        if (TypeExprUser p = cast(TypeExprUser) type)
            return p.kind == TypeExprKind.Enum;
        return false;
    }

    bool isPtr(TypeExpr type)
    {
        return cast(TypeExprPointer) type ? true : false;
    }

public:
    this(Program program, TypeRegistry types, bool[string] staticFunctions, bool noHeader, bool genHeaderFile, 
        string headerFile, ImportResolverContext* context, bool isCpp, TypeResolver resolver, 
        bool haveStackTrace, bool checkNullPtr)
    {
        this.program = program;
        this.types = types;
        this.fnStatics = staticFunctions;
        this.genHeaderFile = genHeaderFile;
        this.headerFile = headerFile;
        this.context = context;
        this.resolver = resolver;
        this.haveStackTrace = haveStackTrace;
        this.checkNullPtr = checkNullPtr;
        if (noHeader) return;
        cxHeader ~= `
#ifndef __CLANG_STDINT_H
  #include <stdint.h>
#endif

#ifndef _STRING_H
   #include <string.h>
#endif

#ifndef __STDDEF_H
   #include <stddef.h>
#endif`;

    if (!isCpp)
        cxHeader ~= `
#ifndef NULL
   #define NULL (void*)0
#endif

#ifndef __STDBOOL_H
   #define true  1
   #define false 0
   #if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
        // ignore
   #else
        #ifndef bool
           typedef int bool;
        #endif
    #endif
#endif

#ifndef CX_STACK_MAX
#define CX_STACK_MAX 1024
#endif

#ifndef CX_NO_TRACE
#include <stdlib.h>

typedef struct {
    const char *fn;
    const char *from;
    const char *file;
    size_t line;
} CxFrame;

static CxFrame __cx_trace[CX_STACK_MAX];
static size_t __cx_head = 0;     // next write slot, wraps around
static size_t __cx_count = 0;    // valid frames, saturates at CX_STACK_MAX
static size_t __cx_dropped = 0;  // total number overwritten

static inline void cx_push(const char *fn, const char *from, size_t line, const char* file) {
    __cx_trace[__cx_head].fn = fn;
    __cx_trace[__cx_head].from = from;
    __cx_trace[__cx_head].line = line;
    __cx_trace[__cx_head].file = file;

    __cx_head = (__cx_head + 1) % CX_STACK_MAX;

    if (__cx_count < CX_STACK_MAX)
        __cx_count++;
    else
        __cx_dropped++; // overwrote the oldest frame, O(1)
}

static inline void cx_pop(void) {
    if (__cx_count > 0) {
        __cx_head = (__cx_head == 0) ? CX_STACK_MAX - 1 : __cx_head - 1;
        __cx_count--;
    }
}

static inline void cx_print_stack(void) {
    if (__cx_count == 0) {
        printf("  (empty stack trace)\n");
        return;
    }
    if (__cx_dropped > 0) {
        printf("  ... %zu oldest frame(s) discarded (limit: %d) ...\n",
               __cx_dropped, CX_STACK_MAX);
    }

    size_t idx = __cx_head;
    size_t n = __cx_count;

    idx = (idx == 0) ? CX_STACK_MAX - 1 : idx - 1;
    CxFrame *top = &__cx_trace[idx];
    printf("  #%zu %s (%s:%zu)\n", n, top->fn, top->file, top->line);

    for (size_t i = 0; i < n; i++) {
        CxFrame *f = &__cx_trace[idx];
        printf("  #%zu %s (%s:%zu)\n", n - 1 - i, f->from, f->file, f->line);
        idx = (idx == 0) ? CX_STACK_MAX - 1 : idx - 1;
    }
}

#else

static inline void cx_print_stack(void) {
    printf("  (stack trace unavailable: binary compiled without stack trace support)\n");
}

#endif

#define __CX_PANIC(msg, file, line) do { \
    fprintf(stderr, "PANIC (%s:%d): %s\n", file, line, msg); \
    fprintf(stderr, "stack trace:\n"); \
    cx_print_stack(); \
    exit(1); \
} while (0)

#define __CX_CALL(fn_name, call_expr, line, file) \
    ({ \
        cx_push(fn_name, __func__, line, file); \
        __typeof__(call_expr) __cx_ret = (call_expr); \
        cx_pop(); \
        __cx_ret; \
    })

#define __CX_CALL_VOID(fn_name, call_expr, line, file) \
    do { \
        cx_push(fn_name, __func__, line, file); \
        (call_expr); \
        cx_pop(); \
    } while (0)

#define __CX_CHECK_NULL_PTR(n, line, file) \
    do { \
        if ((n) == NULL) \
            __CX_PANIC("Attempted to dereference a null pointer.", file, line); \
    } while (0)
`;
    }

    string[2] compile()
    {
        return compileProgram();
    }
}
