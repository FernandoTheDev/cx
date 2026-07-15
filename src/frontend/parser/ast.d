module frontend.parser.ast;

import frontend.lexer.token;
import frontend.type_expr;

import std.array : replicate;
import std.stdio : writeln;
import std.format : format;

enum NodeKind : ubyte
{
    Program, // 1 2

    NumericLit, // 1 2
    DoubleLit, // 1 2
    FloatLit, // 1 2
    BoolLit, // 1 2
    NullLit, // 1 2
    StringLit, // 1 2
    CharLit, // 1 2
    ArrayLit, // 1 2 (n)
    StructLit, // 1 2

    CastExpr, // 1 2
    IdentExpr, // 1 2
    IndexExpr, // 1 2
    MemberExpr, // x.value || x.value() 1 2
    CallExpr, // 1 2
    BinaryExpr, // 1 2
    UnaryExpr, // 1 2
    GroupExpr, // 1 2
    SizeOfExpr, // 1 2
    TypeNameExpr, // 1 2
    IsExpr, // 1 2
    TTypeExpr, // 1 2
    TernaryExpr, // 1 2

    IncludeHeader, // 1 2
    VarDecl, // 1 2
    FnDecl, // 1 2
    StructDecl, // 1 2
    EnumDecl, // 1 2
    UnionDecl, // 1 2
    AliasDecl, // 1 2

    ContinueOrBreakStmt, // 1 2
    IfStmt, // 1 2
    ForStmt, // 1 2
    WhileStmt, // 1 2
    DoWhileStmt,
    GotoStmt, // 1 2
    LabelStmt, // 1 2
    ReturnStmt, // 1 2
    ImportStmt, // 1 2
    AssignStmt, // 1 2
    DeferStmt, // 1 2
    RawStmt, // 1 2
    SwitchStmt, // 1 2
    CaseStmt, // 1 2
}

abstract class Node
{
    NodeKind kind;
    TypeExpr type_expr; // tipo sintatico
    Position pos;

    void print(uint indent);

    // Clonagem profunda e recursiva do nó. Cada subclasse implementa a sua
    // própria versão, retornando uma nova instância totalmente independente
    // (nenhuma referência compartilhada com o original).
    Node dup();

    // Instancia generics: percorre o node (e todos os seus filhos,
    // recursivamente) substituindo qualquer TypeExprNamed cujo nome bata com
    // algum elemento de `names` pelo TypeExpr de mesmo offset em `types`.
    //
    // Não interage com dup() — dup() já deve ter sido chamado antes (para
    // não mutar a AST genérica original); subGeneric() apenas caminha pela
    // árvore já duplicada e resolve os tipos in-place.
    //
    // Nunca desreferencia algo nulo: todo campo Node/TypeExpr/array é
    // checado antes de ser usado.
    void subGeneric(string[] names, TypeExpr[] types);

    this(NodeKind kind, Position pos = Position.init)
    {
        this.kind = kind;
        this.pos = pos;
    }
}

// Helper para duplicar arrays de Node em profundidade, tratando elementos null.
private Node[] dupArr(Node[] arr)
{
    Node[] result;
    result.reserve(arr.length);
    foreach (n; arr)
        result ~= (n is null ? null : n.dup());
    return result;
}

// Aplica subGeneric em cada elemento não-nulo de um array de Node, in-place.
// Seguro mesmo se o array em si estiver vazio ou algum elemento for null.
private void subGenericArr(Node[] arr, string[] names, TypeExpr[] types)
{
    foreach (n; arr)
    {
        if (n !is null)
            n.subGeneric(names, types);
    }
}

// Resolve o type_expr do próprio nó (campo `type_expr` de Node), tratando
// nulo e aplicando a mesma lógica de substituição usada em type_expr.d
// (resolveGeneric é private naquele módulo, então replicamos aqui).
// Retorna o novo valor a ser atribuído a node.type_expr.
private TypeExpr subGenericType(TypeExpr t, string[] names, TypeExpr[] types)
{
    if (t is null)
        return null;

    if (names.length != types.length)
        return t;

    if (auto named = cast(TypeExprNamed) t)
    {
        foreach (i, n; names)
            if (n == named.name)
                return types[i].dup();
        return t;
    }

    // Não é Named direto (ex: Pointer/Array/Function/Result): desce
    // recursivamente na própria árvore de tipos para pegar Nameds aninhados.
    return t.subGeneric(names, types);
}

class Program : Node
{
    Node[] body;

    this(Node[] body)
    {
        super(NodeKind.Program);
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        iprint(indent, "Program");
        foreach (node; body)
            node.print(indent + 1);
    }

    override Program dup()
    {
        auto n = new Program(dupArr(body));
        n.kind = kind;
        n.pos = pos;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        subGenericArr(body, names, types);
    }
}

class NumericLit : Node
{
    bool isLong;
    union
    {
        ulong u;
        long l;
    }

    this(bool isLong, long l, Position pos)
    {
        super(NodeKind.NumericLit, pos);
        if (isLong)
            this.type_expr = new TypeExprNamed("int", pos);
        else
            this.type_expr = new TypeExprNamed("ulong", pos);
        this.isLong = isLong;
        this.l = l;
    }

    override void print(uint indent)
    {
        string repr = isLong
            ? format("NumericLit long=%d", l) : format("NumericLit u=%d", u);
        iprint(indent, repr);
    }

    override NumericLit dup()
    {
        // union: copiamos a representação bruta via 'l'/'u' que compartilham
        // o mesmo armazenamento, então basta copiar um dos dois campos.
        auto n = new NumericLit(isLong, l, pos);
        n.u = u; // garante bit-a-bit idêntico independente de isLong
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class DoubleLit : Node
{
    double val;

    this(double val, Position pos)
    {
        super(NodeKind.DoubleLit, pos);
        this.type_expr = new TypeExprNamed("double", pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, format("DoubleLit %g", val));
    }

    override DoubleLit dup()
    {
        auto n = new DoubleLit(val, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class FloatLit : Node
{
    float val;

    this(float val, Position pos)
    {
        super(NodeKind.FloatLit, pos);
        this.type_expr = new TypeExprNamed("float", pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, format("FloatLit %g", val));
    }

    override FloatLit dup()
    {
        auto n = new FloatLit(val, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class BoolLit : Node
{
    bool val;

    this(bool val, Position pos)
    {
        super(NodeKind.BoolLit, pos);
        this.type_expr = new TypeExprNamed("bool", pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, val ? "BoolLit true" : "BoolLit false");
    }

    override BoolLit dup()
    {
        auto n = new BoolLit(val, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class NullLit : Node
{
    this(Position pos)
    {
        super(NodeKind.NullLit, pos);
        this.type_expr = new TypeExprPointer(new TypeExprNamed("void", pos), pos);
    }

    override void print(uint indent)
    {
        iprint(indent, "NullLit");
    }

    override NullLit dup()
    {
        auto n = new NullLit(pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }

}

class StringLit : Node
{
    string val;

    this(string val, Position pos)
    {
        super(NodeKind.StringLit, pos);
        this.type_expr = new TypeExprPointer(new TypeExprNamed("char", pos), pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, format(`StringLit "%s"`, val));
    }

    override StringLit dup()
    {
        // string em D é imutável (immutable(char)[]), então val ~ ""
        // não é necessário para "clonar" o conteúdo, mas mantemos explícito.
        auto n = new StringLit(val, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class CharLit : Node
{
    char val;

    this(char val, Position pos)
    {
        super(NodeKind.CharLit, pos);
        this.type_expr = new TypeExprNamed("char", pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, format("CharLit '%s'", val));
    }

    override CharLit dup()
    {
        auto n = new CharLit(val, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class CastExpr : Node
{
    Node expr;

    this(Node expr, TypeExpr t, Position pos)
    {
        super(NodeKind.CastExpr, pos);
        this.type_expr = t;
        this.expr = expr;
    }

    override void print(uint indent)
    {
        iprint(indent, format("CastExpr to=%s", type_expr));
        expr.print(indent + 1);
    }

    override CastExpr dup()
    {
        auto n = new CastExpr(
            expr is null ? null : cast(Node) expr.dup(),
            type_expr is null ? null : type_expr.dup(),
            pos
        );
        n.kind = kind;
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (expr !is null)
            expr.subGeneric(names, types);
    }

}

class VarDecl : Node
{
    string name;
    Node val;
    bool isConst;

    this(string name, Node val, bool isConst, TypeExpr t, Position pos)
    {
        super(NodeKind.VarDecl, pos);
        this.name = name;
        this.isConst = isConst;
        this.type_expr = t;
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, format("VarDecl name=%s const=%s type=%s",
                name, isConst, type_expr));
        if (val !is null)
            val.print(indent + 1);
    }

    override VarDecl dup()
    {
        auto n = new VarDecl(
            name,
            val is null ? null : cast(Node) val.dup(),
            isConst,
            type_expr is null ? null : type_expr.dup(),
            pos
        );
        n.kind = kind;
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (val !is null)
            val.subGeneric(names, types);
    }
}

class FnArg
{
    string name;
    TypeExpr type_expr;
    Node val;
    Position pos;

    this(string name, TypeExpr type_expr, Node val, Position pos)
    {
        this.name = name;
        this.type_expr = type_expr;
        this.val = val;
        this.pos = pos;
    }

    FnArg dup()
    {
        return new FnArg(
            name,
            type_expr is null ? null : type_expr.dup(),
            val is null ? null : cast(Node) val.dup(),
            pos
        );
    }

    void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (val !is null)
            val.subGeneric(names, types);
    }
}

class FnDecl : Node
{
    string name;
    FnArg[] args;
    Node[] body;
    ubyte flags;

    this(string name, FnArg[] args, Node[] body, TypeExpr t, Position pos, ubyte flags = 0)
    {
        super(NodeKind.FnDecl, pos);
        this.name = name;
        this.args = args;
        this.type_expr = t;
        this.body = body;
        this.flags = flags;
    }

    override void print(uint indent)
    {
        string header = format("FnDecl %s ret=%s", name, type_expr);
        iprint(indent, header);

        foreach (arg; args)
        {
            iprint(indent + 1, format("Arg name=%s type=%s", arg.name, arg.type_expr));
            if (arg.val !is null)
                arg.val.print(indent + 2);
        }

        foreach (stmt; body)
            stmt.print(indent + 1);
    }

    override FnDecl dup()
    {
        FnArg[] argsCopy;
        argsCopy.reserve(args.length);
        foreach (a; args)
            argsCopy ~= (a is null ? null : a.dup());

        auto n = new FnDecl(
            name,
            argsCopy,
            dupArr(body),
            type_expr is null ? null : type_expr.dup(),
            pos,
            flags
        );
        n.kind = kind;
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        foreach (a; args)
        {
            if (a !is null)
                a.subGeneric(names, types);
        }
        subGenericArr(body, names, types);
    }
}

class ReturnStmt : Node
{
    Node val;

    this(Node val, Position pos)
    {
        super(NodeKind.ReturnStmt, pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, "ReturnStmt");
        if (val !is null)
            val.print(indent + 1);
    }

    override ReturnStmt dup()
    {
        auto n = new ReturnStmt(val is null ? null : cast(Node) val.dup(), pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (val !is null)
            val.subGeneric(names, types);
    }
}

class IdentExpr : Node
{
    string val;

    this(string val, TypeExpr type, Position pos)
    {
        super(NodeKind.IdentExpr, pos);
        this.type_expr = type;
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, format("IdentExpr %s (%s)", val, type_expr));
    }

    override IdentExpr dup()
    {
        auto n = new IdentExpr(val, type_expr is null ? null : type_expr.dup(), pos);
        n.kind = kind;
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class BinaryExpr : Node
{
    Node left, right;
    TokenKind op;

    this(Node left, Node right, TokenKind op, Position pos)
    {
        super(NodeKind.BinaryExpr, pos);
        this.left = left;
        this.right = right;
        this.op = op;
    }

    override void print(uint indent)
    {
        iprint(indent, format("BinaryExpr op=%s", op));
        left.print(indent + 1);
        right.print(indent + 1);
    }

    override BinaryExpr dup()
    {
        auto n = new BinaryExpr(
            left is null ? null : cast(Node) left.dup(),
            right is null ? null : cast(Node) right.dup(),
            op,
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (left !is null)
            left.subGeneric(names, types);
        if (right !is null)
            right.subGeneric(names, types);
    }
}

class UnaryExpr : Node
{
    Node val;
    TokenKind op;
    bool post;

    this(Node val, TokenKind op, Position pos, bool post)
    {
        super(NodeKind.UnaryExpr, pos);
        this.val = val;
        this.op = op;
        this.post = post;
    }

    override void print(uint indent)
    {
        iprint(indent, format("UnaryExpr op=%s", op));
        val.print(indent + 1);
    }

    override UnaryExpr dup()
    {
        auto n = new UnaryExpr(
            val is null ? null : cast(Node) val.dup(),
            op,
            pos,
            post
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (val !is null)
            val.subGeneric(names, types);
    }
}

class AssignStmt : Node
{
    Node left, right;
    TokenKind op;

    this(Node left, Node right, TokenKind op, Position pos)
    {
        super(NodeKind.AssignStmt, pos);
        this.left = left;
        this.right = right;
        this.op = op;
    }

    override void print(uint indent)
    {
        iprint(indent, format("AssignStmt op=%s", op));
        left.print(indent + 1);
        right.print(indent + 1);
    }

    override AssignStmt dup()
    {
        auto n = new AssignStmt(
            left is null ? null : cast(Node) left.dup(),
            right is null ? null : cast(Node) right.dup(),
            op,
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (left !is null)
            left.subGeneric(names, types);
        if (right !is null)
            right.subGeneric(names, types);
    }
}

class MemberExpr : Node
{
    Node left, right;

    this(Node left, Node right, Position pos)
    {
        super(NodeKind.MemberExpr, pos);
        this.left = left;
        this.right = right;
    }

    override void print(uint indent)
    {
        iprint(indent, "MemberExpr");
        left.print(indent + 1);
        right.print(indent + 1);
    }

    override MemberExpr dup()
    {
        auto n = new MemberExpr(
            left is null ? null : cast(Node) left.dup(),
            right is null ? null : cast(Node) right.dup(),
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (left !is null)
            left.subGeneric(names, types);
        if (right !is null)
            right.subGeneric(names, types);
    }
}

class CallExpr : Node
{
    Node callee;
    Node[] args;

    this(Node callee, Node[] args, Position pos)
    {
        super(NodeKind.CallExpr, pos);
        this.callee = callee;
        this.args = args;
    }

    override void print(uint indent)
    {
        iprint(indent, "CallExpr");
        callee.print(indent + 1);
        foreach (arg; args)
            arg.print(indent + 1);
    }

    override CallExpr dup()
    {
        auto n = new CallExpr(
            callee is null ? null : cast(Node) callee.dup(),
            dupArr(args),
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (callee !is null)
            callee.subGeneric(names, types);
        subGenericArr(args, names, types);
    }
}

class IndexExpr : Node
{
    Node value, idx;

    this(Node value, Node idx, Position pos)
    {
        super(NodeKind.IndexExpr, pos);
        this.value = value;
        this.idx = idx;
    }

    override void print(uint indent)
    {
        iprint(indent, "IndexExpr");
        iprint(indent, "Idx");
        idx.print(indent + 1);
        iprint(indent, "Value");
        value.print(indent + 1);
    }

    override IndexExpr dup()
    {
        auto n = new IndexExpr(
            value is null ? null : cast(Node) value.dup(),
            idx is null ? null : cast(Node) idx.dup(),
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (value !is null)
            value.subGeneric(names, types);
        if (idx !is null)
            idx.subGeneric(names, types);
    }
}

class SizeOfExpr : Node
{
    this(TypeExpr expr, Position pos)
    {
        super(NodeKind.SizeOfExpr, pos);
        this.type_expr = expr;
    }

    override void print(uint indent)
    {
        iprint(indent, format("SizeOfExpr type=%s", type_expr));
    }

    override SizeOfExpr dup()
    {
        auto n = new SizeOfExpr(type_expr is null ? null : type_expr.dup(), pos);
        n.kind = kind;
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class IncludeHeader : Node
{
    string code;
    this(string code)
    {
        super(NodeKind.IncludeHeader, Position.init);
        this.code = code;
    }

    override void print(uint indent)
    {
        iprint(indent, format("IncludeHeader: %s", code));
    }

    override IncludeHeader dup()
    {
        auto n = new IncludeHeader(code);
        n.kind = kind;
        n.pos = pos;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class StructDecl : Node
{
    string name;
    string[] genericT;
    UnionDecl[] unions;
    StructDecl[] structs;
    VarDecl[] fields;
    FnDecl[] functions;
    bool fromGeneric;

    this(string name, VarDecl[] fields, FnDecl[] functions, 
       UnionDecl[] unions, StructDecl[] structs, string[] genericT, Position pos, bool fromGeneric = false)
    {
        super(NodeKind.StructDecl, pos);
        this.name = name;
        this.fields = fields;
        this.functions = functions;
        this.genericT = genericT;
        this.fromGeneric = fromGeneric;
        this.structs = structs;
        this.unions = unions;
        this.type_expr = new TypeExprUser(TypeExprKind.Struct, name, pos);
    }

    override void print(uint indent)
    {
        iprint(indent, format("StructDecl: %s", name));
    }

    override StructDecl dup()
    {
        VarDecl[] fieldsCopy;
        fieldsCopy.reserve(fields.length);
        foreach (f; fields)
            fieldsCopy ~= (f is null ? null : f.dup());

        FnDecl[] functionsCopy;
        functionsCopy.reserve(functions.length);
        foreach (fn; functions)
            functionsCopy ~= (fn is null ? null : fn.dup());

        StructDecl[] structsCopy;
        structsCopy.reserve(structs.length);
        foreach (st; structs)
            structsCopy ~= (st is null ? null : st.dup());

        UnionDecl[] unionsCopy;
        unionsCopy.reserve(unions.length);
        foreach (un; unions)
            unionsCopy ~= (un is null ? null : un.dup());

        auto n = new StructDecl(name, fieldsCopy, functionsCopy, unions, structs, (string[]).init, pos, fromGeneric);
        if (!fromGeneric)
            n.fromGeneric = genericT.length > 0;
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        foreach (f; fields)
        {
            if (f !is null)
                f.subGeneric(names, types);
        }
        foreach (fn; functions)
        {
            if (fn !is null)
                fn.subGeneric(names, types);
        }
    }
}

class StructLit : Node
{
    Node[] values;
    this(Node[] values, Position pos)
    {
        super(NodeKind.StructLit, pos);
        this.values = values;
    }

    override void print(uint indent)
    {
        iprint(indent, "StructLit");
    }

    override StructLit dup()
    {
        auto n = new StructLit(dupArr(values), pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        subGenericArr(values, names, types);
    }
}

class DeferStmt : Node
{
    Node val;
    this(Node val, Position pos)
    {
        super(NodeKind.DeferStmt, pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, "DeferStmt");
    }

    override DeferStmt dup()
    {
        auto n = new DeferStmt(val is null ? null : cast(Node) val.dup(), pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (val !is null)
            val.subGeneric(names, types);
    }
}

class IfStmt : Node
{
    Node expr;
    Node[] body;
    IfStmt _else;
    bool isElse;

    this(Node expr, Node[] body, IfStmt _else, bool isElse, Position pos)
    {
        super(NodeKind.IfStmt, pos);
        this.expr = expr;
        this.body = body;
        this._else = _else;
        this.isElse = isElse;
    }

    override void print(uint indent)
    {
        iprint(indent, "IfStmt");
    }

    override IfStmt dup()
    {
        auto n = new IfStmt(
            expr is null ? null : cast(Node) expr.dup(),
            dupArr(body),
            _else is null ? null : _else.dup(),
            isElse,
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (expr !is null)
            expr.subGeneric(names, types);
        subGenericArr(body, names, types);
        if (_else !is null)
            _else.subGeneric(names, types);
    }
}

class GroupExpr : Node
{
    Node val;
    this(Node val, Position pos)
    {
        super(NodeKind.GroupExpr, pos);
        this.val = val;
    }

    override void print(uint indent)
    {
        iprint(indent, "GroupExpr");
    }

    override GroupExpr dup()
    {
        auto n = new GroupExpr(val is null ? null : cast(Node) val.dup(), pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (val !is null)
            val.subGeneric(names, types);
    }
}

class WhileStmt : Node
{
    Node expr;
    Node[] body;

    this(Node expr, Node[] body, Position pos)
    {
        super(NodeKind.WhileStmt, pos);
        this.expr = expr;
        this.body = body;
    }

    override void print(uint indent)
    {
        iprint(indent, "WhileStmt");
    }

    override WhileStmt dup()
    {
        auto n = new WhileStmt(
            expr is null ? null : cast(Node) expr.dup(),
            dupArr(body),
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (expr !is null)
            expr.subGeneric(names, types);
        subGenericArr(body, names, types);
    }
}

class ForStmt : Node
{
    Node first, middle, end;
    Node[] body;

    this(Node first, Node middle, Node end, Node[] body, Position pos)
    {
        super(NodeKind.ForStmt, pos);
        this.first = first;
        this.middle = middle;
        this.end = end;
        this.body = body;
    }

    override void print(uint indent)
    {
        iprint(indent, "ForStmt");
    }

    override ForStmt dup()
    {
        auto n = new ForStmt(
            first is null ? null : cast(Node) first.dup(),
            middle is null ? null : cast(Node) middle.dup(),
            end is null ? null : cast(Node) end.dup(),
            dupArr(body),
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (first !is null)
            first.subGeneric(names, types);
        if (middle !is null)
            middle.subGeneric(names, types);
        if (end !is null)
            end.subGeneric(names, types);
        subGenericArr(body, names, types);
    }
}

class ContinueOrBreakStmt : Node
{
    bool isBreak;
    this(bool isBreak, Position pos)
    {
        super(NodeKind.ContinueOrBreakStmt, pos);
        this.isBreak = isBreak;
    }

    override void print(uint indent)
    {
        iprint(indent, "ContinueOrBreakStmt");
    }

    override ContinueOrBreakStmt dup()
    {
        auto n = new ContinueOrBreakStmt(isBreak, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class EnumDecl : Node
{
    string name;
    string[] fields;

    this(string name, string[] fields, Position pos)
    {
        super(NodeKind.EnumDecl, pos);
        this.name = name;
        this.fields = fields;
        this.type_expr = new TypeExprUser(TypeExprKind.Enum, name, pos);
    }

    override void print(uint indent)
    {
        iprint(indent, "EnumDecl");
    }

    override EnumDecl dup()
    {
        // string[] -> cada elemento é string imutável; .dup copia o array
        // (o slice), preservando o conteúdo isoladamente do original.
        auto n = new EnumDecl(name, fields.dup, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        // `fields` aqui é string[] (nomes dos membros do enum), não há
        // TypeExpr para substituir além do type_expr do próprio nó.
        type_expr = subGenericType(type_expr, names, types);
    }
}

class UnionDecl : Node
{
    string name;
    TypeExpr[string] fields;

    this(string name, TypeExpr[string] fields, Position pos)
    {
        super(NodeKind.UnionDecl, pos);
        this.name = name;
        this.fields = fields;
        this.type_expr = new TypeExprUser(TypeExprKind.Union, name, pos);
    }

    override void print(uint indent)
    {
        iprint(indent, "UnionDecl");
    }

    override UnionDecl dup()
    {
        TypeExpr[string] fieldsCopy;
        foreach (key, value; fields)
            fieldsCopy[key] = (value is null ? null : value.dup());

        auto n = new UnionDecl(name, fieldsCopy, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        foreach (key; fields.keys)
            fields[key] = subGenericType(fields[key], names, types);
    }
}

class AliasDecl : Node
{
    string name;
    this(string name, Position pos)
    {
        super(NodeKind.AliasDecl, pos);
        this.name = name;
    }

    override void print(uint indent)
    {
        iprint(indent, "AliasDecl");
    }

    override AliasDecl dup()
    {
        auto n = new AliasDecl(name, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class ImportStmt : Node
{
    string file;
    this(string file, Position pos)
    {
        super(NodeKind.ImportStmt, pos);
        this.file = file;
    }

    override void print(uint indent)
    {
        iprint(indent, "ImportStmt");
    }

    override ImportStmt dup()
    {
        auto n = new ImportStmt(file, pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class GotoStmt : Node
{
    Node label;
    this(Node label, Position pos)
    {
        super(NodeKind.GotoStmt, pos);
        this.label = label;
    }

    override void print(uint indent)
    {
        iprint(indent, "GotoStmt");
    }

    override GotoStmt dup()
    {
        auto n = new GotoStmt(label.dup(), pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
    }
}

class LabelStmt : Node
{
    string name;
    Node[] body;
    this(string name, Node[] body, Position pos)
    {
        super(NodeKind.LabelStmt, pos);
        this.name = name;
        this.body = body;
    }

    override void print(uint indent)
    {
        iprint(indent, "LabelStmt");
    }

    override LabelStmt dup()
    {
        auto n = new LabelStmt(name, dupArr(body), pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        subGenericArr(body, names, types);
    }
}

class ArrayLit : Node
{
    Node[] values;
    this(Node[] values, Position pos)
    {
        super(NodeKind.ArrayLit, pos);
        this.values = values;
    }

    override void print(uint indent)
    {
        iprint(indent, "ArrayLit");
    }

    override ArrayLit dup()
    {
        auto n = new ArrayLit(dupArr(values), pos);
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        subGenericArr(values, names, types);
    }
}

class RawStmt : Node
{
    string code;
    this(string code, Position pos)
    {
        super(NodeKind.RawStmt, pos);
        this.code = code;
    }

    override void print(uint indent)
    {
        iprint(indent, "RawStmt");
    }

    override RawStmt dup()
    {
        return new RawStmt(code, pos);
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        //
    }
}

class SwitchStmt : Node
{
    Node expr;
    CaseStmt[] cases;

    this(Node expr, CaseStmt[] cases, Position pos)
    {
        super(NodeKind.SwitchStmt, pos);
        this.expr = expr;
        this.cases = cases;
    }

    override void print(uint indent)
    {
        iprint(indent, "SwitchStmt");
        if (expr !is null)
            expr.print(indent + 1);
        foreach (c; cases)
            c.print(indent + 1);
    }

    override SwitchStmt dup()
    {
        CaseStmt[] casesCopy;
        casesCopy.reserve(cases.length);
        foreach (c; cases)
            casesCopy ~= (c is null ? null : c.dup());

        auto n = new SwitchStmt(
            expr is null ? null : cast(Node) expr.dup(),
            casesCopy,
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (expr !is null)
            expr.subGeneric(names, types);
        foreach (c; cases)
        {
            if (c !is null)
                c.subGeneric(names, types);
        }
    }
}

class CaseStmt : Node
{
    Node value; // null se for 'default'
    bool hasVar;
    Node[] body;

    this(Node value, bool hasVar, Node[] body, Position pos)
    {
        super(NodeKind.CaseStmt, pos);
        this.value = value;
        this.body = body;
        this.hasVar = hasVar;
    }

    override void print(uint indent)
    {
        if (value is null)
            iprint(indent, "CaseStmt default");
        else
        {
            iprint(indent, "CaseStmt");
            value.print(indent + 1);
        }
        foreach (stmt; body)
            stmt.print(indent + 1);
    }

    override CaseStmt dup()
    {
        auto n = new CaseStmt(
            value is null ? null : cast(Node) value.dup(),
            hasVar,
            dupArr(body),
            pos
        );
        n.kind = kind;
        n.type_expr = type_expr is null ? null : type_expr.dup();
        return n;
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type_expr = subGenericType(type_expr, names, types);
        if (value !is null)
            value.subGeneric(names, types);
        subGenericArr(body, names, types);
    }
}

class TypeNameExpr : Node
{
    Node expr;

    this(Node expr, Position pos)
    {
        super(NodeKind.TypeNameExpr, pos);
        this.expr = expr;
        type_expr = new TypeExprPointer(new TypeExprNamed("char", pos), pos);
    }

    override void print(uint indent)
    {
        iprint(indent, "TypeNameExpr");
    }

    override TypeNameExpr dup()
    {
        return new TypeNameExpr(expr.dup(), pos);
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        expr.subGeneric(names, types);
    }
}

class TTypeExpr : Node
{
    TypeExpr type;

    this(TypeExpr expr, Position pos)
    {
        super(NodeKind.TTypeExpr, pos);
        this.type = expr;
        type_expr = new TypeExprPointer(new TypeExprNamed("char", pos), pos);
    }

    override void print(uint indent)
    {
        iprint(indent, "TTypeExpr");
    }

    override TTypeExpr dup()
    {
        return new TTypeExpr(type.dup(), pos);
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        type = subGenericType(type, names, types);
    }
}

class IsExpr : Node
{
    TypeExpr left, right;
    this(TypeExpr left, TypeExpr right, Position pos)
    {
        super(NodeKind.IsExpr, pos);
        this.left = left;
        this.right = right;
        type_expr = new TypeExprNamed("int", pos);
    }

    override void print(uint indent)
    {
        iprint(indent, "IsExpr");
    }

    override IsExpr dup()
    {
        return new IsExpr(left.dup(), right.dup(), pos);
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        left = subGenericType(left, names, types);
        right = subGenericType(right, names, types);
    }
}

class TernaryExpr : Node
{
    Node expr, left, right;

    this(Node expr, Node left, Node right, Position pos)
    {
        super(NodeKind.TernaryExpr, pos);
        this.expr = expr;
        this.left = left;
        this.right = right;
    }

    override void print(uint indent)
    {
        iprint(indent, "TernaryExpr");
    }

    override TernaryExpr dup()
    {
        return new TernaryExpr(expr.dup(), left.dup(), right.dup(), pos);
    }

    override void subGeneric(string[] names, TypeExpr[] types)
    {
        expr.subGeneric(names, types);
        left.subGeneric(names, types);
        right.subGeneric(names, types);
    }
}

pragma(inline, true)
private void iprint(uint indent, string s)
{
    writeln("  ".replicate(indent) ~ s);
}

enum NodeFlags : ubyte
{
    Inline = 0b00000001,
    Static = 0b00000010,
    Overload = 0b00000100,
}
