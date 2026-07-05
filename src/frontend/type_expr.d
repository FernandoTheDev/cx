// tipo sintatico
module frontend.type_expr;

import frontend.lexer : Position;

import std.format;
import std.stdio;

enum TypeExprKind : ubyte
{
    Array,
    Named,
    Pointer,
    Struct,
    Union,
    Enum,
    Function,
    Result,
    Generic,
}

abstract class TypeExpr
{
    TypeExprKind kind;
    Position pos;
    override string toString() const;
    string toStrVar(string var = "") const;
    string toStr() const;
    TypeExpr dup();

    // Substitui, recursivamente, todo TypeExprNamed cujo nome bate com algum
    // elemento de `names` pelo TypeExpr correspondente (mesmo offset) em
    // `types`. Usado pelo sistema de generics para instanciar um tipo
    // genérico (ex: T, T*, T[N]) com o tipo concreto passado.
    //
    // Este método muta a árvore de tipos IN-PLACE quando possível (campos
    // internos como `base`, `ret`, `args[i]`, `ok`, `error`), mas como um
    // TypeExprNamed no topo da árvore não tem "filho" para mutar (ele PRÓPRIO
    // é o alvo da substituição), quem contém a referência ao TypeExpr (seja
    // um Node ou um TypeExpr pai) deve reatribuir o campo usando o valor de
    // retorno desta função.
    //
    // Retorna o próprio `this` (já mutado) ou um TypeExpr substituto quando
    // o nó raiz precisar ser trocado inteiramente.
    TypeExpr subGeneric(string[] names, TypeExpr[] types);

    // Percorre recursivamente esta árvore de tipos, invocando `callback`
    // para cada TypeExprGeneric encontrado (incluindo o próprio `this`, se
    // for um TypeExprGeneric, e quaisquer instâncias aninhadas dentro de
    // args). Usado para descobrir, depois de uma instanciação de generics,
    // quais OUTRAS instanciações genéricas ficaram "expostas" dentro do
    // corpo gerado (ex: Cool<int> contendo uma chamada a Entry<int> em seu
    // próprio corpo) e portanto também precisam ser geradas em cascata.
    //
    // Nunca desreferencia ponteiros nulos.
    void collectGenerics(void delegate(TypeExprGeneric) callback);

    // Verifica, recursivamente, se esta árvore de tipos referencia algum
    // nome para o qual `isOpen(name)` retorna true — isto é, se contém
    // (em qualquer profundidade: dentro de ponteiros, arrays, argumentos de
    // função/generic, etc) um TypeExprNamed cujo nome é atualmente um
    // parâmetro genérico "em aberto" no parser (ex: T dentro do corpo de
    // struct Cool<T>).
    //
    // Usado para decidir se uma instanciação de tipo genérico encontrada
    // durante o parse (ex: Entry<T>) é uma instanciação REAL com tipo
    // concreto, ou apenas uma referência ao parâmetro genérico cru do
    // struct que a contém — neste último caso ela não deve ser enfileirada
    // para monomorfização diretamente.
    //
    // Nunca desreferencia ponteiros nulos.
    bool containsOpenGeneric(bool delegate(string) isOpen);
}

// Resolve o TypeExpr substituto para `t`, dado o mapeamento names -> types.
// Retorna `t` inalterado (após aplicar subGeneric recursivamente nele, se
// aplicável) quando não há correspondência, ou o tipo substituto quando há.
// Nunca desreferencia ponteiros nulos.
private TypeExpr resolveGeneric(TypeExpr t, string[] names, TypeExpr[] types)
{
    if (t is null)
        return null;

    if (names.length != types.length)
        return t;

    if (auto named = cast(TypeExprNamed) t)
    {
        foreach (i, n; names)
        {
            if (n == named.name)
                return types[i];
        }
        return t;
    }

    // Não é um Named direto: desce recursivamente para substituir eventuais
    // Named aninhados (ex: dentro de um Pointer/Array/Function/Result).
    return t.subGeneric(names, types);
}

class TypeExprNamed : TypeExpr
{
    string name;

    this(string name, Position p = Position.init)
    {
        this.kind = TypeExprKind.Named;
        this.name = name;
        this.pos = p;
    }

    override string toString() const
    {
        return toStrVar();
    }

    override string toStrVar(string var = "") const
    {
        return name ~ (var == "" ? "" : " " ~ var);
    }

    override string toStr() const
    {
        return name;
    }

    override TypeExprNamed dup()
    {
        auto n = new TypeExprNamed(name, pos);
        n.kind = kind;
        return n;
    }

    override TypeExpr subGeneric(string[] names, TypeExpr[] types)
    {
        // TypeExprNamed não tem filhos internos: a própria substituição
        // (se houver) é decidida por quem chama, via resolveGeneric().
        // Aqui não há nada para mutar, então apenas retornamos `this`.
        return this;
    }

    override void collectGenerics(void delegate(TypeExprGeneric) callback)
    {
        // Folha, não é TypeExprGeneric e não tem filhos: nada a coletar.
    }

    override bool containsOpenGeneric(bool delegate(string) isOpen)
    {
        return isOpen(name);
    }
}

class TypeExprArray : TypeExpr
{
    TypeExpr base;
    string idx;

    this(TypeExpr base, string idx, Position p = Position.init)
    {
        this.kind = TypeExprKind.Array;
        this.base = base;
        this.idx = idx;
        this.pos = p;
    }

    override string toString() const
    {
        return toStrVar();
    }

    override string toStrVar(string var = "") const
    {
        return base.toStrVar() ~ (var == "" ? "" : " " ~ var) ~ format("[%s]", idx);
    }

    override string toStr() const
    {
        return base.toStr();
    }

    override TypeExprArray dup()
    {
        auto n = new TypeExprArray(base is null ? null : base.dup(), idx, pos);
        n.kind = kind;
        return n;
    }

    override TypeExpr subGeneric(string[] names, TypeExpr[] types)
    {
        base = resolveGeneric(base, names, types);
        return this;
    }

    override void collectGenerics(void delegate(TypeExprGeneric) callback)
    {
        if (base !is null)
            base.collectGenerics(callback);
    }

    override bool containsOpenGeneric(bool delegate(string) isOpen)
    {
        return base !is null && base.containsOpenGeneric(isOpen);
    }
}

class TypeExprPointer : TypeExpr
{
    TypeExpr base;

    this(TypeExpr base, Position p = Position.init)
    {
        this.kind = TypeExprKind.Pointer;
        this.base = base;
        this.pos = p;
    }

    override string toString() const
    {
        return toStrVar();
    }

    override string toStrVar(string var = "") const
    {
        return base.toStrVar() ~ "*" ~ (var == "" ? "" : " " ~ var);
    }

    override string toStr() const
    {
        return base.toStr();
    }

    override TypeExprPointer dup()
    {
        auto n = new TypeExprPointer(base is null ? null : base.dup(), pos);
        n.kind = kind;
        return n;
    }

    override TypeExpr subGeneric(string[] names, TypeExpr[] types)
    {
        base = resolveGeneric(base, names, types);
        return this;
    }

    override void collectGenerics(void delegate(TypeExprGeneric) callback)
    {
        if (base !is null)
            base.collectGenerics(callback);
    }

    override bool containsOpenGeneric(bool delegate(string) isOpen)
    {
        return base !is null && base.containsOpenGeneric(isOpen);
    }
}

class TypeExprUser : TypeExpr
{
    string name;

    this(TypeExprKind kind, string name, Position p)
    {
        this.kind = kind;
        this.name = name;
        this.pos = p;
    }

    override string toString() const
    {
        return toStrVar();
    }

    override string toStrVar(string var = "") const
    {
        return name ~ (var == "" ? "" : " " ~ var);
    }

    override string toStr() const
    {
        return name;
    }

    override TypeExprUser dup()
    {
        return new TypeExprUser(kind, name, pos);
    }

    override TypeExpr subGeneric(string[] names, TypeExpr[] types)
    {
        // TypeExprUser (struct/union/enum já resolvido) não encapsula outro
        // TypeExpr, então não há nada para substituir aqui dentro.
        return this;
    }

    override void collectGenerics(void delegate(TypeExprGeneric) callback)
    {
        // Não encapsula outro TypeExpr; nada a coletar.
    }

    override bool containsOpenGeneric(bool delegate(string) isOpen)
    {
        // TypeExprUser é um tipo já resolvido (struct/union/enum concreto),
        // não um nome de parâmetro genérico em aberto.
        return false;
    }
}

class TypeExprFunction : TypeExpr
{
    TypeExpr ret;
    TypeExpr[] args;

    this(TypeExpr ret, TypeExpr[] args, Position p = Position.init)
    {
        this.kind = TypeExprKind.Function;
        this.ret = ret;
        this.args = args;
        this.pos = p;
    }

    override string toString() const
    {
        return toStrVar();
    }

    override string toStrVar(string var = "") const
    {
        string _;
        for (ulong i; i < args.length; i++)
        {
            _ ~= args[i].toStrVar();
            if ((i + 1) < args.length)
                _ ~= ", ";
        }
        return format("%s(*%s)(%s)", ret.toStrVar(), var, _);
    }

    override string toStr() const
    {
        return toStrVar();
    }

    override TypeExprFunction dup()
    {
        TypeExpr[] argsCopy;
        argsCopy.reserve(args.length);
        foreach (a; args)
            argsCopy ~= (a is null ? null : a.dup());
        auto n = new TypeExprFunction(ret is null ? null : ret.dup(), argsCopy, pos);
        n.kind = kind;
        return n;
    }

    override TypeExpr subGeneric(string[] names, TypeExpr[] types)
    {
        ret = resolveGeneric(ret, names, types);
        foreach (i, a; args)
            args[i] = resolveGeneric(a, names, types);
        return this;
    }

    override void collectGenerics(void delegate(TypeExprGeneric) callback)
    {
        if (ret !is null)
            ret.collectGenerics(callback);
        foreach (a; args)
        {
            if (a !is null)
                a.collectGenerics(callback);
        }
    }

    override bool containsOpenGeneric(bool delegate(string) isOpen)
    {
        if (ret !is null && ret.containsOpenGeneric(isOpen))
            return true;
        foreach (a; args)
        {
            if (a !is null && a.containsOpenGeneric(isOpen))
                return true;
        }
        return false;
    }
}

class TypeExprResult : TypeExpr
{
    TypeExpr ok, error;

    this(TypeExpr ok, TypeExpr error, Position p = Position.init)
    {
        this.kind = TypeExprKind.Result;
        this.ok = ok;
        this.error = error;
        this.pos = p;
    }

    override string toString() const
    {
        return toStrVar();
    }

    override string toStrVar(string var = "") const
    {
        return format("%s%s", ok.toStr(), error.toStr()) ~ (var == "" ? "" : " " ~ var);
    }

    override string toStr() const
    {
        return toStrVar();
    }

    override TypeExprResult dup()
    {
        auto n = new TypeExprResult(
            ok is null ? null : ok.dup(),
            error is null ? null : error.dup(),
            pos
        );
        n.kind = kind;
        return n;
    }

    override TypeExpr subGeneric(string[] names, TypeExpr[] types)
    {
        ok = resolveGeneric(ok, names, types);
        error = resolveGeneric(error, names, types);
        return this;
    }

    override void collectGenerics(void delegate(TypeExprGeneric) callback)
    {
        if (ok !is null)
            ok.collectGenerics(callback);
        if (error !is null)
            error.collectGenerics(callback);
    }

    override bool containsOpenGeneric(bool delegate(string) isOpen)
    {
        return (ok !is null && ok.containsOpenGeneric(isOpen))
            || (error !is null && error.containsOpenGeneric(isOpen));
    }
}

// Representa um tipo genérico instanciado, isto é, o USO de um tipo genérico
// com argumentos concretos (ou ainda genéricos, se aninhado) já aplicados.
// Exemplos: List<int>, Map<K, V>, Pair<T, string>.
//
// `name` é o nome base do tipo genérico (ex: "List", "Map", "Pair").
// `args` é a lista ordenada dos argumentos de tipo (ex: [int] para List<int>,
// [K, V] para Map<K, V>).
//
// A representação textual (toStr/toStrVar) usa um "name mangling" simples,
// concatenando o nome base com o toStr() de cada argumento separado por
// underscore: List<int> -> "List_int", Map<K, V> -> "Map_K_V".
class TypeExprGeneric : TypeExpr
{
    string name;
    TypeExpr[] args;

    this(string name, TypeExpr[] args, Position p = Position.init)
    {
        this.kind = TypeExprKind.Generic;
        this.name = name;
        this.args = args;
        this.pos = p;
    }

    override string toString() const
    {
        return toStrVar();
    }

    override string toStrVar(string var = "") const
    {
        return toStr() ~ (var == "" ? "" : " " ~ var);
    }

    override string toStr() const
    {
        // Mangling simples: Nome_Tipo1_Tipo2...
        string result = name;
        foreach (a; args)
        {
            // args pode conter elementos nulos em estados intermediários
            // (ex: durante parsing); protegemos contra isso ao invés de
            // segfaultar chamando toStr() num ponteiro nulo.
            result ~= "_" ~ (a is null ? "?" : a.toStr());
        }
        return result;
    }

    override TypeExprGeneric dup()
    {
        TypeExpr[] argsCopy;
        argsCopy.reserve(args.length);
        foreach (a; args)
            argsCopy ~= (a is null ? null : a.dup());
        auto n = new TypeExprGeneric(name, argsCopy, pos);
        n.kind = kind;
        return n;
    }

    override TypeExpr subGeneric(string[] names, TypeExpr[] types)
    {
        foreach (i, a; args)
            args[i] = resolveGeneric(a, names, types);
        import main : generic;
        // writeln("name: ", name, " ", types);
        generic.add(name, types);
        return this;
    }

    override void collectGenerics(void delegate(TypeExprGeneric) callback)
    {
        callback(this);
        foreach (a; args)
        {
            if (a !is null)
                a.collectGenerics(callback);
        }
    }

    override bool containsOpenGeneric(bool delegate(string) isOpen)
    {
        foreach (a; args)
        {
            if (a !is null && a.containsOpenGeneric(isOpen))
                return true;
        }
        return false;
    }
}
