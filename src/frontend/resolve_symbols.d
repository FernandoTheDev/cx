module frontend.resolve_symbols;

import frontend;

import std.format;
import std.stdio;

class ResolveSymbols
{
    static Node[] resolve(Diagnostics err, ImportResolverContext* context, Node[] body, string base = "")
    {
        Node[] newBody;
        foreach (Node node; body)
        {
            string name; 
            if (node.kind == NodeKind.FnDecl)
            {
                FnDecl fn = cast(FnDecl)node;
                name = fn.name;
                if (!(fn.flags & NodeFlags.Overload))
                    name = base == "" ? name : format("%s_%s", base, name);
                // writeln("Sym: ", name);
            }
            else if (node.kind == NodeKind.StructDecl)
            {
                StructDecl s = cast(StructDecl)node;
                if (s.genericT.length == 0)
                {
                    name = s.name;
                    // writeln("Name: ", name);
                    resolve(err, context, cast(Node[]) s.functions, name);
                }
            }
            else if (node.kind == NodeKind.EnumDecl)
                name = (cast(EnumDecl)node).name;
            else if (node.kind == NodeKind.UnionDecl)
                name = (cast(UnionDecl)node).name;
            else if (node.kind == NodeKind.AliasDecl)
                name = (cast(AliasDecl)node).name;
            if (name != "")
                if (Node* p = name in context.symbols)
                {
                    if (p.pos.filename == node.pos.filename)
                    {
                        err.warning(node.pos,
                            format("The symbol '%s' was declared twice in the same file, first declaration: %s",
                                name, p.toString()));
                        continue;
                    }
                }
            newBody ~= node;
            context.symbols[name] = node;
        }
        return newBody;
    }
}
