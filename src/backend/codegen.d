module backend.codegen;

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
    TypeExpr actualType;
    TypeExpr fnType;
    bool genHeaderFile;
    string headerFile;
    ImportResolverContext* context;

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
            return compileStructDecl(as!StructDecl(node), ind);

        case NodeKind.EnumDecl:
            return compileEnumDecl(as!EnumDecl(node), ind);

        case NodeKind.UnionDecl:
            return compileUnionDecl(as!UnionDecl(node), ind);

        case NodeKind.AliasDecl:
        case NodeKind.ImportStmt:
            return;

        default:
            emit("/* invalid decl */", ind);
            return;
        }
    }

    void compileUnionDecl(UnionDecl node, uint ind)
    {
        string name = node.name;
        typedefs ~= format("typedef union %s %s;", name, name);
        string _data = format("union %s\n{\n", name);
        foreach (string field, TypeExpr type; node.fields)
            _data ~= indent(format("%s %s;\n", type.toString(), field), ind + 4);
        _data ~= "};\n";
        data ~= _data;
    }

    void compileEnumDecl(EnumDecl node, uint ind)
    {
        string name = node.name;
        typedefs ~= format("typedef enum %s %s;", name, name);
        string _data = format("enum %s\n{\n", name);
        foreach (string field; node.fields)
            _data ~= indent(format("%s_%s,\n", name, field), ind + 4);
        _data ~= "};\n";
        data ~= _data;
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
            return compileRetDecl(as!ReturnStmt(node), ind);

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
            emit(format("%s:", n.name), ind);
            foreach (Node _; n.body)
                emit(compileStmt(_, ind), ind);
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
            if (isString(binary.left.type_expr) && isString(binary.right.type_expr) && binary.op == TokenKind
                .EEEquals)
                return format("strcmp(%s, %s) == 0", left, right);
            return format("%s %s %s", left, getOp(binary.op), right);

        case NodeKind.UnaryExpr:
            UnaryExpr un = cast(UnaryExpr) node;
            string op = getOp(un.op);
            string val = compileExpr(un.val);
            return format("%s%s", un.post ? val : op, un.post ? op : val);

        case NodeKind.StringLit:
            return '"' ~ (cast(StringLit) node).val ~ '"';

        case NodeKind.CharLit:
            return "'" ~ (cast(CharLit) node).val ~ "'";

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
            string values;
            for (ulong i; i < strc.values.length; i++)
            {
                values ~= compileExpr(strc.values[i]);
                if ((i + 1) < strc.values.length)
                    values ~= ", ";
            }
            return format("{%s}", values);

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
            IndexExpr idx = cast(IndexExpr) node;
            return format("%s[%s]", compileExpr(idx.value), compileExpr(idx.idx));

        case NodeKind.GroupExpr:
            return "(" ~ compileExpr((cast(GroupExpr) node).val) ~ ")";

        case NodeKind.SizeOfExpr:
            SizeOfExpr sz = cast(SizeOfExpr) node;
            return format("sizeof(%s)", sz.type_expr.toString());

        default:
            return "/* invalid expr */";
        }
    }

    void emitBody(Node[] body, uint ind)
    {
        bool cond = body.length > 1 || defer.length > 0 || body.length == 0;
        if (cond)
            emit("{", ind);
        foreach (Node node; body)
            emit(compileStmt(node, ind), ind);
        if (cond)
            emit("}", ind);
    }

    string compileIfStmt(IfStmt node, uint ind)
    {
        if (node.expr !is null)
        {
            emit(format("if (%s)", compileExpr(node.expr)), ind);
            emitBody(node.body, ind);
        }
        else
        {
            emit("else", ind);
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

        if (isString(type) && node.right.kind == NodeKind.IdentExpr)
            if ((cast(IdentExpr) node.right).val == "length")
                return format("strlen(%s)", compileExpr(node.left));

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
                id = format("tmp_%d", tmp++);
                emit(format("%s %s = %s;", m.right.type_expr, id, compileMemberExpr(m)), 4);
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
        if (type !is null)
            if (type.kind == TypeExprKind.Enum || (type.kind == TypeExprKind.Struct && types.exists(left)))
                symbol = "_";

        return format("%s%s%s", left, symbol, compileExpr(
                node.right));
    }

    string compileCallExpr(CallExpr node, bool fromMethod = false, string var = "", string typeName = "")
    {
        string args = fromMethod ? var : "";
        if (node.args.length > 0 && fromMethod)
            args ~= ", ";
        for (ulong i; i < node.args.length; i++)
        {
            Node arg = node.args[i];
            args ~= compileExpr(arg);
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
        return format("%s(%s)", clearNameMangling(callee), args);
    }

    string compileCallStmt(CallExpr node, uint ind)
    {
        return indent(format("%s;", compileCallExpr(node)), ind);
    }

    string compileRetDecl(ReturnStmt node, uint ind)
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
            // writeln(node.val.type_expr);
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
        return indent(format("return %s%s;", val == "self" && fnType !is null ? "*" : "", val), ind);
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
        _data ~= "};\n";
        data ~= _data;
        foreach (FnDecl fn; node.functions)
            compileFnDecl(fn, ind, true, name, node.fromGeneric);
        actualType = a;
    }

    string clearNameMangling(string name)
    {
        string buff;
        for (ulong i; i < name.length; i++)
            if (name[i] == '*')
                buff ~= 'P';
            else
                buff ~= name[i];
        return buff;
    }

    void compileFnDecl(FnDecl fn, uint ind, bool isMethod = false, string methodType = "", bool fromGeneric = false)
    {
        defer = []; // limpa
        fnType = fn.type_expr;
        string args;
        bool hasSelf = !(fn.flags & NodeFlags.Static);
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
    // string proto = format("%s%s", fn.type_expr.toStrVar(isMethod ? format("%s_%s", methodType, name)
    //             : name),
    //         cond ? "" : format("(%s)", args));
        // string proto = format("%s(%s)", , args);
        protos ~= proto ~ ";";
        emit(proto, ind);
        emit("{", ind);
        proto ~= " {\n";
        bool error = fnErrorUnion;
        fnErrorUnion = fn.type_expr.kind == TypeExprKind.Result;
        if (fnErrorUnion)
        {
            TypeExprResult res = cast(TypeExprResult) fn.type_expr;
            fnUnion = res.toString();
            fnError[0] = res.ok;
            fnError[1] = res.error;

            if (fnUnion !in errorUnions)
            {
                // adiciona no data para gerar depois, assim como o typedef
                errorUnions[fnUnion] = true;
                typedefs ~= format("typedef struct %s %s;", fnUnion, fnUnion);
                data ~= format("struct %s { bool valid; union { %s ok; %s error; } val; };", fnUnion,
                    res.ok.toStr(), res.error.toStr());
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
        if (!hasReturn)
            deferResolve(ind+4);
        fnErrorUnion = error;
        emit("}\n", ind);
    }

    void deferResolve(uint ind)
    {
        if (defer.length == 0)
            return;
        // comportamento LIFO
        foreach_reverse (string def; defer)
            emit(def, ind);
    }

    bool isString(TypeExpr type)
    {
        if (TypeExprPointer p = cast(TypeExprPointer) type)
            if (TypeExprNamed t = cast(TypeExprNamed) p.base)
                return t.name == "char";
        return false;
    }

    bool isResult(TypeExpr type)
    {
        if (TypeExprFunction f = cast(TypeExprFunction) type)
            return isResult(f.ret);
        if (type is null)
            return false;
        return type.kind == TypeExprKind.Result;
    }

public:
    this(Program program, TypeRegistry types, bool[string] staticFunctions, bool noHeader, bool genHeaderFile, 
        string headerFile, ImportResolverContext* context)
    {
        this.program = program;
        this.types = types;
        this.fnStatics = staticFunctions;
        this.genHeaderFile = genHeaderFile;
        this.headerFile = headerFile;
        this.context = context;
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
#endif

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
#endif`;
    }

    string[2] compile()
    {
        return compileProgram();
    }
}
