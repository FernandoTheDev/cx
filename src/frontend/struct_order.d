module frontend.struct_order;

import frontend;

import std.array : join;
import std.format;
import std.stdio;

final class StructOrder
{
private:
    Diagnostics err;
    size_t[string] indexOf;
    Node[] nodes;
    size_t[] slots;
    size_t[][] adj;

    string nameOf(Node n)
    {
        if (auto s = cast(StructDecl) n)
            return s.name;
        if (auto u = cast(UnionDecl) n)
            return u.name;
        if (auto e = cast(EnumDecl) n)
            return e.name;
        return "";
    }

    bool participates(Node n)
    {
        if (auto s = cast(StructDecl) n)
            return s.genericT.length == 0;
        if (cast(UnionDecl) n)
            return true;
        if (cast(EnumDecl) n)
            return true;
        return false;
    }

    void collectValueDeps(TypeExpr t, ref bool[string] deps)
    {
        if (t is null)
            return;

        switch (t.kind)
        {
        case TypeExprKind.Struct:
        case TypeExprKind.Union:
        case TypeExprKind.Enum:
        case TypeExprKind.Generic:
            deps[t.toStr()] = true;
            return;

        case TypeExprKind.Array:
            collectValueDeps((cast(TypeExprArray) t).base, deps);
            return;

        case TypeExprKind.Const:
            collectValueDeps((cast(TypeExprConst) t).base, deps);
            return;

        case TypeExprKind.Volatile:
            collectValueDeps((cast(TypeExprVolatile) t).base, deps);
            return;
        
        case TypeExprKind.Restrict:
            collectValueDeps((cast(TypeExprRestrict) t).base, deps);
            return;
        
        case TypeExprKind.Atomic:
            collectValueDeps((cast(TypeExprAtomic) t).base, deps);
            return;
        
        default:
            return;
        }
    }

    bool[string] fieldDeps(StructDecl s)
    {
        bool[string] deps;
        // writeln(s.name);
        foreach (VarDecl f; s.fields)
            if (f !is null)
                collectValueDeps(f.type_expr, deps);
        foreach (UnionDecl u; s.unions)
            if (u !is null)
                foreach (name, TypeExpr ft; u.fields)
                    collectValueDeps(ft, deps);
        return deps;
    }

    // Dependências de campo de uma UnionDecl top-level.
    bool[string] fieldDeps(UnionDecl u)
    {
        bool[string] deps;
        foreach (name, TypeExpr ft; u.fields)
            collectValueDeps(ft, deps);
        return deps;
    }

    void buildGraph()
    {
        foreach (i, Node n; nodes)
        {
            bool[string] deps;
            if (auto s = cast(StructDecl) n)
                deps = fieldDeps(s);
            else if (auto u = cast(UnionDecl) n)
                deps = fieldDeps(u);
            // EnumDecl nunca tem campos -> deps vazio, adj[i] fica [].

            foreach (depName, _; deps)
            {
                if (depName == nameOf(n))
                    continue; // recursão direta (ex: ponteiro pra si mesma) já foi filtrada por não descer em Pointer; isto é defesa extra
                if (auto j = depName in indexOf)
                    adj[i] ~= *j;
                // se depName não está em indexOf, é um tipo builtin ou uma
                // struct genérica não-instanciada residual: não participa
                // do grafo, então simplesmente não gera aresta.
            }
        }
    }

    // Kahn's algorithm. Retorna a ordem topológica (índices em `nodes`) se
    // não há ciclo. Se sobra algum nó com in-degree > 0, `remaining`
    // recebe esses índices (o ciclo, ou os ciclos, estão contidos neles) e
    // a função retorna um array vazio.
    size_t[] topoSort(out size_t[] remaining)
    {
        size_t n = nodes.length;

        // adj[i] = lista de nós dos quais i depende (aresta lógica
        // dep -> i: "dep deve ser emitido antes de i"). Logo, o in-degree
        // de Kahn's para o nó i (quantas dependências pendentes ele tem)
        // é simplesmente adj[i].length.
        int[] indeg = new int[n];
        foreach (i; 0 .. n)
            indeg[i] = cast(int) adj[i].length;

        // fila com todos os nós sem dependência pendente, na ordem
        // original (desempate estável = ordem de aparição em program.body)
        size_t[] queue;
        foreach (i; 0 .. n)
            if (indeg[i] == 0)
                queue ~= i;

        // quem depende de mim (aresta inversa), construído sob demanda
        size_t[][] dependents = new size_t[][n];
        foreach (i; 0 .. n)
            foreach (dep; adj[i])
                dependents[dep] ~= i;

        size_t[] order;
        order.reserve(n);
        size_t head;
        while (head < queue.length)
        {
            size_t cur = queue[head++];
            order ~= cur;
            foreach (dependent; dependents[cur])
            {
                indeg[dependent]--;
                if (indeg[dependent] == 0)
                    queue ~= dependent;
            }
        }

        if (order.length == n)
            return order;

        // sobrou gente: coleta quem não foi processado (indeg[i] > 0
        // ainda), preservando a ordem original.
        foreach (i; 0 .. n)
            if (indeg[i] > 0)
                remaining ~= i;
        return [];
    }

    // DFS auxiliar, usada SOMENTE no caminho de erro, pra extrair um ciclo
    // concreto (não apenas "estes N nós formam algum ciclo") de dentro do
    // subconjunto `remaining` devolvido por topoSort. Isso separa nós que
    // só "alimentam" o ciclo (apontam pra ele mas não estão nele) do ciclo
    // de fato, pra mensagem de erro citar exatamente A -> B -> A.
    string[] findCycle(size_t[] remaining)
    {
        bool[size_t] inRemaining;
        foreach (r; remaining)
            inRemaining[r] = true;

        int[size_t] state; // 0 = não visitado, 1 = na pilha atual, 2 = concluído
        size_t[] stack;
        string[] result;

        bool visit(size_t node)
        {
            state[node] = 1;
            stack ~= node;

            foreach (dep; adj[node])
            {
                if ((dep in inRemaining) is null)
                    continue; // fora do subconjunto restante, não pode fazer parte do ciclo
                auto st = dep in state;
                if (st is null || *st == 0)
                {
                    if (visit(dep))
                        return true;
                }
                else if (*st == 1)
                {
                    // achou o ciclo: reconstrói a partir de onde `dep`
                    // aparece na pilha até o topo
                    size_t startIdx;
                    foreach (k, s; stack)
                        if (s == dep)
                        {
                            startIdx = k;
                            break;
                        }
                    foreach (s; stack[startIdx .. $])
                        result ~= nameOf(nodes[s]);
                    result ~= nameOf(nodes[dep]); // fecha o ciclo
                    return true;
                }
            }

            stack = stack[0 .. $ - 1];
            state[node] = 2;
            return false;
        }

        foreach (r; remaining)
        {
            if ((r in state) is null || state[r] == 0)
                if (visit(r))
                    break;
        }

        return result;
    }

    void reportCycle(size_t[] remaining)
    {
        // invariante: só chegamos aqui quando topoSort() já constatou
        // order.length != nodes.length com nodes.length > 0, então sempre
        // sobra pelo menos um índice em `remaining`.
        assert(remaining.length > 0);

        string[] cycle = findCycle(remaining);
        string path = cycle.length > 0 ? cycle.join(" -> ") : "(não foi possível reconstruir o caminho exato)";

        // usa a posição do primeiro nó do ciclo encontrado, ou do primeiro
        // nó restante como fallback, pra apontar o erro em algum lugar útil
        Position pos = nodes[remaining[0]].pos;
        if (cycle.length > 0)
            if (auto idx = cycle[0] in indexOf)
                pos = nodes[*idx].pos;

        err.error(pos, format(
            "Circular dependency detected between types: %s. "
            ~ "A type cannot contain, by value, a field of a type that (directly or indirectly) contains it in return. "
            ~ "Use a pointer on one side of the cycle to break the dependency.",
            path));
    }

public:
    this(Diagnostics err)
    {
        this.err = err;
    }

    void resolve(Program program)
    {        
        foreach (i, Node n; program.body)
        {
            if (!participates(n))
                continue;
            string name = nameOf(n);
            if (name == "")
                continue;
            indexOf[name] = nodes.length;
            nodes ~= n;
            slots ~= i;
        }

        if (nodes.length == 0)
            return;

        adj = new size_t[][nodes.length];
        buildGraph();

        size_t[] remaining;
        size_t[] order = topoSort(remaining);

        if (order.length == 0)
        {
            reportCycle(remaining);
            return;
        }

        // reinsere os nós, na ordem topológica, nos mesmos slots
        // originais. slots já está em ordem crescente (foi construído
        // percorrendo program.body de 0 em diante), então basta mapear
        // order[k] -> slots[k].
        for (ulong i; i < order.length; i++)
            program.body[slots[i]] = nodes[order[i]];
    }
}
