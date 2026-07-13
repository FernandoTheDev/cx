module frontend.type_resolve;

import frontend;

import std.format;
import std.stdio;

final class Scope
{
    Scope parent;
    TypeExpr[string] vars;

    this(Scope parent = null)
    {
        this.parent = parent;
    }

    void declare(string name, TypeExpr t)
    {
        vars[name] = t;
    }

    TypeExpr lookup(string name)
    {
        if (auto t = name in vars)
            return *t;
        if (parent !is null)
            return parent.lookup(name);
        return null;
    }
}

final class TypeResolver
{
private:
    TypeRegistry types;
    TypeExpr currentSelfType; // tipo (sem ponteiro) da struct dona do método atual

    // nome da struct -> declaração completa, pra achar campos e métodos
    StructDecl[string] structs;
    TypeExpr[string] functions;

    void collectDecls(Program program)
    {
        foreach (node; program.body)
            if (node.kind == NodeKind.StructDecl)
                structs[(cast(StructDecl) node).name] = cast(StructDecl) node;
    }

    TypeExpr unwrapPointer(TypeExpr t)
    {
        if (t !is null && t.kind == TypeExprKind.Pointer)
            return (cast(TypeExprPointer) t).base;
        return t;
    }

    string baseName(TypeExpr t)
    {
        return t.toStr();
    }

    VarDecl findField(string structName, string fieldName)
    {
        if (auto s = structName in structs)
            foreach (f; (*s).fields)
                if (f.name == fieldName)
                    return f;
        return null;
    }

    FnDecl findMethod(string structName, string methodName)
    {
        if (auto s = structName in structs)
            foreach (fn; (*s).functions)
                if (fn.name == methodName)
                    return fn;
        return null;
    }

    TypeExpr resolveExprType(Node n, Scope scp)
    {
        if (n is null)
            return null;

        switch (n.kind)
        {
        case NodeKind.IdentExpr:
            IdentExpr id = cast(IdentExpr) n;
            if (id.val == "self" && currentSelfType !is null)
            {
                id.type_expr = new TypeExprPointer(currentSelfType);
                return id.type_expr;
            }
            TypeExpr t = scp.lookup(id.val);
            if (t !is null)
                id.type_expr = t;
            return id.type_expr; // se não achar, mantém o que já tinha (provavelmente null)

        case NodeKind.MemberExpr:
            return resolveMemberExpr(cast(MemberExpr) n, scp);

        case NodeKind.CallExpr:
            return resolveCallExpr(cast(CallExpr) n, scp);

        case NodeKind.UnaryExpr:
            UnaryExpr u = cast(UnaryExpr) n;
            TypeExpr inner = resolveExprType(u.val, scp);
            TypeExpr result = inner;
            if (u.op == TokenKind.Star && inner !is null && inner.kind == TypeExprKind.Pointer)
                result = (cast(TypeExprPointer) inner).base;
            else if (u.op == TokenKind.BITAnd && inner !is null)
                result = new TypeExprPointer(inner);
            u.type_expr = result;
            return result;

        case NodeKind.IndexExpr:
            IndexExpr idx = cast(IndexExpr) n;
            TypeExpr baseType = resolveExprType(idx.value, scp);
            resolveExprType(idx.idx, scp);
            TypeExpr elemType;
            if (baseType !is null && baseType.kind == TypeExprKind.Array)
                elemType = (cast(TypeExprArray) baseType).base;
            else if (baseType !is null && baseType.kind == TypeExprKind.Pointer)
                elemType = (cast(TypeExprPointer) baseType).base;
            idx.type_expr = elemType;
            return elemType;

        case NodeKind.GroupExpr:
            TypeExpr t = resolveExprType((cast(GroupExpr) n).val, scp);
            n.type_expr = t;
            return t;

        case NodeKind.BinaryExpr:
            BinaryExpr b = cast(BinaryExpr) n;
            TypeExpr lt = resolveExprType(b.left, scp);
            resolveExprType(b.right, scp);
            b.type_expr = lt; // aproximação: tipo do lado esquerdo domina
            return lt;

        case NodeKind.AssignStmt:
            AssignStmt a = cast(AssignStmt) n;
            resolveExprType(a.right, scp);
            TypeExpr lt2 = resolveExprType(a.left, scp);
            a.type_expr = lt2;
            return lt2;

        case NodeKind.CastExpr:
            CastExpr c = (cast(CastExpr) n);
            resolveExprType(c.expr, scp);
            if (c.expr.type_expr is null) c.expr.type_expr = c.type_expr;
            return c.type_expr; // já veio do parser

        case NodeKind.StructLit:
            foreach (v; (cast(StructLit) n).values)
                resolveExprType(v, scp);
            return n.type_expr;

        case NodeKind.ArrayLit:
            foreach (v; (cast(ArrayLit) n).values)
                resolveExprType(v, scp);
            return n.type_expr;

        case NodeKind.ReturnStmt:
            // writeln("RET");
            ReturnStmt ret = cast(ReturnStmt) n;
            if (ret.val is null) return TypeExpr.init;
            TypeExpr t = resolveExprType(ret.val, scp);
            return t;

        default:
            // já vêm com type_expr setado no próprio construtor
            return n.type_expr;
        }
    }

    TypeExpr resolveMemberExpr(MemberExpr m, Scope scp)
    {
        // caso especial: right é uma chamada de método -> a.metodo(...)
        if (m.right.kind == NodeKind.CallExpr)
        {
            CallExpr call = cast(CallExpr) m.right;
            foreach (arg; call.args)
                resolveExprType(arg, scp);

            TypeExpr leftType = resolveExprType(m.left, scp);
            m.left.type_expr = leftType;

            string sName;
            if (m.left.kind == NodeKind.IdentExpr && types.exists((cast(IdentExpr) m.left).val))
                sName = (cast(IdentExpr) m.left).val; // chamada estática: Tipo.metodo()
            else
                sName = baseName(leftType); // chamada de instância: valor.metodo()

            string methodName;
            if (call.callee.kind == NodeKind.IdentExpr)
                methodName = (cast(IdentExpr) call.callee).val;

            FnDecl fn = findMethod(sName, methodName);
            if (fn is null)
                // fallback
                fn = findMethod(sName, format("%s_%s", sName, methodName));
            TypeExpr ret = fn !is null ? fn.type_expr : m.left.type_expr;
            // writeln("Name: ", sName, " ", methodName, " ", fn, " ", ret);

            m.type_expr = ret;
            m.right.type_expr = ret;
            return ret;
        }

        // caso normal: a.campo (ou a->campo)
        TypeExpr leftType = resolveExprType(m.left, scp);
        m.left.type_expr = leftType;

        string sName = baseName(leftType);
        TypeExpr fieldType = null;

        if (leftType !is null && m.right !is null)
            if (leftType.kind == TypeExprKind.Result && m.right.kind == NodeKind.IdentExpr)
            {
                string fieldName = (cast(IdentExpr) m.right).val;
                TypeExprResult res = cast(TypeExprResult) leftType;
                if (fieldName == "ok") {
                    fieldType = res.ok;
                    m.right.type_expr = fieldType;
                }
                else if (fieldName == "error") {
                    fieldType = res.error;
                    m.right.type_expr = fieldType;
                }
                else if (fieldName == "valid") {
                    fieldType = *types.get("bool");
                    m.right.type_expr = fieldType;
                }
            }

        if (sName !is null && m.right.kind == NodeKind.IdentExpr && fieldType is null)
        {
            string fieldName = (cast(IdentExpr) m.right).val;
            VarDecl field = findField(sName, fieldName);
            if (field !is null)
            {
                fieldType = field.type_expr;
                m.right.type_expr = fieldType;
            }
            else if (leftType !is null && leftType.kind == TypeExprKind.Enum)
                // Tipo_CAMPO de enum: não tem "tipo de campo" per se, o próprio enum é o tipo
                fieldType = leftType;
        }

        // import std.conv;
        // stderr.writefln("[member] left.kind=%s leftType=%s (kind=%s) sName=%s fieldType=%s",
        //     m.left.kind, leftType, leftType is null ? "NULL" : to!string(leftType.kind), sName, fieldType);

        m.type_expr = fieldType;
        return fieldType;
    }

    TypeExpr resolveCallExpr(CallExpr c, Scope scp)
    {
        foreach (arg; c.args)
            resolveExprType(arg, scp);

        if (c.callee.kind != NodeKind.IdentExpr)
            resolveExprType(c.callee, scp);
        else {
            string callee = (cast(IdentExpr)c.callee).val;
            // writeln("Callee: ", callee);
            // writeln(functions, "\n");
            if (TypeExpr* t = callee in functions)
                c.type_expr = *t;
            else
                c.type_expr = scp.lookup(callee);
        }

        return c.type_expr;
    }

    void resolveStmt(Node n, Scope scp)
    {
        if (n is null)
            return;

        switch (n.kind)
        {
        case NodeKind.VarDecl:
            VarDecl v = cast(VarDecl) n;
            if (v.val !is null)
            {
                resolveExprType(v.val, scp);
                if (v.val.type_expr is null) v.val.type_expr = v.type_expr;
            }
            scp.declare(v.name, v.type_expr);
            return;

        case NodeKind.ReturnStmt:
            resolveExprType((cast(ReturnStmt) n).val, scp);
            return;

        case NodeKind.IfStmt:
            IfStmt i = cast(IfStmt) n;
            if (i.expr !is null)
                resolveExprType(i.expr, scp);
            resolveBody(i.body, new Scope(scp));
            if (i._else !is null)
                resolveStmt(i._else, scp);
            return;

        case NodeKind.WhileStmt:
            WhileStmt w = cast(WhileStmt) n;
            resolveExprType(w.expr, scp);
            resolveBody(w.body, new Scope(scp));
            return;

        case NodeKind.ForStmt:
            ForStmt f = cast(ForStmt) n;
            Scope inner = new Scope(scp);
            if (f.first !is null)
                resolveStmt(f.first, inner);
            if (f.middle !is null)
                resolveExprType(f.middle, inner);
            if (f.end !is null)
                resolveExprType(f.end, inner);
            resolveBody(f.body, inner);
            return;

        case NodeKind.DeferStmt:
            resolveExprType((cast(DeferStmt) n).val, scp);
            return;

        case NodeKind.ContinueOrBreakStmt:
            return;

        default:
            // CallExpr, MemberExpr, AssignStmt, UnaryExpr usados como statement
            resolveExprType(n, scp);
            return;
        }
    }

    void resolveBody(Node[] body, Scope scp)
    {
        foreach (n; body)
            resolveStmt(n, scp);
    }

    void resolveFnDecl(FnDecl fn, string ownerName)
    {
        Scope scp = new Scope(null);
        functions[fn.name] = fn.type_expr;
        if (ownerName !is null && !(fn.flags & NodeFlags.Static))
            scp.declare("self", new TypeExprPointer(*types.get(ownerName)));
        foreach (arg; fn.args)
            scp.declare(arg.name, arg.type_expr);
        resolveBody(fn.body, scp);
    }

public:
    this(TypeRegistry types)
    {
        this.types = types;
    }

    void resolve(Program program)
    {
        collectDecls(program);
        foreach (node; program.body)
        {
            if (node.kind == NodeKind.FnDecl)
                resolveFnDecl(cast(FnDecl) node, null);
            else if (node.kind == NodeKind.StructDecl)
            {
                StructDecl s = cast(StructDecl) node;
                currentSelfType = *types.get(s.name);
                foreach (fn; s.functions)
                    resolveFnDecl(fn, s.name);
                currentSelfType = null;
            }
        }
    }
}
