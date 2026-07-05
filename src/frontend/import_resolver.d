module frontend.import_resolver;

import frontend;

import main : check_diagnostic;
import std.stdio;
import std.file;

struct ImportResolverContext
{
    string[string] mods; // módulos resolvidos
    Position[string] symbols; // simbolos globais
    bool[string] statics;
}

class ImportResolver
{
private:
    string mod; // módulo atual
    Diagnostics err;
    TypeRegistry registry;
    ImportResolverContext* context;
    Generic generic;
    Program program;

public:
    this(ImportResolverContext* context, Program program, Diagnostics err, TypeRegistry registry, Generic generic)
    {
        this.context = context;
        this.program = program;
        this.err = err;
        this.registry = registry;
        this.generic = generic;
    }

    void resolve()
    {
        Node[] body; // novo corpo do programa atual
        ImportStmt[] imports;
        
        foreach (Node node; program.body)
            if (node.kind == NodeKind.ImportStmt)
                imports ~= cast(ImportStmt) node;

        if (imports.length == 0)
            return;

        string path = imports[0].pos.dir;
        string filename = imports[0].pos.filename;
        mod = path ~ filename; // monta o modulo atual com base na posição
        
        foreach (ImportStmt im; imports)
        {
            string file = im.file;
            string file_ = path ~ file;
            if (!exists(file_) || !isFile(file_))
            {
                err.error(im.pos, "Non-existent module.");
                continue;
            }

            if (string* m = file in context.mods)
            {
                if (*m == mod)
                    err.error(im.pos, "The module was imported twice by the same file.");
                continue;
            }

            context.mods[file] = mod;

            string content = readText(file_);
            Lexer l = new Lexer(file, path, content, err, registry);
            Token[] tokens = l.tokenizer();
	        check_diagnostic(err);

	        Parser p = new Parser(tokens, err, registry, generic, context);
	        Program prog = p.parse();
	        check_diagnostic(err);

	        new ImportResolver(context, prog, err, registry, generic).resolve();
            body ~= prog.body;
        }
        
        body ~= program.body;
        program.body = body;
    }
}
