module frontend.generic;

import frontend;

import std.array : join;
import std.format;
import std.stdio;

class Generic
{
    TypeRegistry registry;
    Node[string] symbols; // todos os simbolos genericos (ex: "Calc" -> StructDecl original)
    TypeExpr[][][string] qeue; // pedidos sob demanda para monomorfização: name -> lista de instanciações, cada instanciação é a lista completa de tipos (ex: [int], [float] para Calc<T>; [int, string] para Pair<K,V>)
    string[string] gen; // chave = nome mangled já gerado (ex: "Calc_int"), evita duplicação

    this(TypeRegistry registry)
    {
        this.registry = registry;
    }

    void set(string name, Node node)
    {
        symbols[name] = node;
    }

    // Registra um pedido de instanciação. `types` é a lista COMPLETA e
    // ordenada dos argumentos de tipo para essa instanciação (ex: para
    // Pair<K, V> instanciado como Pair<int, string>, types = [int, string]).
    // Cada chamada representa UMA instanciação, nunca um parâmetro isolado.
    void add(string name, TypeExpr[] types)
    {
        // name = Calc
        // types = [int]      -> Calc_int
        qeue[name] ~= [types];
    }

    void setGen(string name)
    {
        gen[name] = name;
    }

    // Constrói o nome mangled de uma instanciação, protegendo contra tipos
    // nulos (usa "?" como placeholder ao invés de segfaultar).
    private string mangledName(string baseName, TypeExpr[] types)
    {
        string result = baseName;
        foreach (t; types)
            result ~= "_" ~ (t is null ? "?" : t.toStr());
        return result;
    }

    void resolve(Program program)
    {
        // writeln(symbols);
        // writeln(qeue);
        // writeln(gen);
        foreach (string name, Node symbol; symbols)
        {
            if (symbol is null)
                continue;

            if (symbol.kind != NodeKind.StructDecl)
                continue;

            TypeExpr[][]* instantiations = name in qeue;
            if (instantiations is null)
                continue;

            StructDecl s = cast(StructDecl) symbol;
            if (s is null)
                continue;

            string[] genericT = s.genericT;
            string templt = format("%s_%s", name, genericT.join("_"));
            // string[string] Ts;
            // foreach (string s; genericT)
            //     Ts[s] = s;

            foreach (TypeExpr[] types; *instantiations)
            {
                // Segurança: se o número de argumentos não bate com o
                // número de parâmetros genéricos declarados, pula essa
                // instanciação em vez de gerar uma struct incorreta ou
                // indexar fora dos limites dentro de subGeneric.
                if (types.length != genericT.length)
                    continue;

                string mangled = name;
                bool err;
                foreach (t; types)
                {
                    if (!registry.exists(t.toStr()))
                        err = true;
                    mangled ~= "_" ~ (t is null ? "?" : t.toStr());
                }

                // writeln(mangled == templt, " ", mangled, " ", templt, " ", err);
                if (err)
                    continue;

                if (mangled == templt)
                    continue;

                // Já foi gerada antes (mesma combinação exata de tipos)?
                if (mangled in gen)
                    continue;

                // FIX: resolve o problema do template ser gerado
                // if (registry.exists(mangled))
                //     continue;

                gen[mangled] = mangled;
                registry.set(mangled, new TypeExprUser(TypeExprKind.Struct, mangled, symbol.pos));

                // dup() primeiro: nunca mutamos o StructDecl genérico
                // original, senão a próxima instanciação (ex: Calc<float>
                // depois de Calc<int>) operaria sobre uma árvore já
                // substituída pela instanciação anterior.
                StructDecl n = s.dup();
                n.name = mangled;
                n.subGeneric(genericT, types);
                // Node[] body = n ~ program.body;
                program.body ~= n;
            }
        }
    }
}
