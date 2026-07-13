module frontend.import_resolver;

import frontend;
import utils;

import main : check_diagnostic;
import std.format;
import std.array;
import std.stdio;
import std.file;
import std.path;

struct ImportResolverContext
{
    string cxdir;
    string[string] mods; // módulos resolvidos
    Node[string] symbols; // simbolos globais
    bool[string] statics;
}

class ImportResolver
{
private:
    string mod; // módulo atual
    Diagnostics err;
    TypeRegistry registry;
    ImportResolverContext* context;
    ImportResolverContext* local;
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

    bool fileExists(string file)
    {
        if (!exists(file))
            return false;
        return true;
    }

    Node[] importFile(string file, ImportStmt im, string mod, string file_, string path)
    {
        if (string* m = file in context.mods)
        {
            // writeln(file);
            // writeln(context.mods);
            if (*m == mod)
                err.error(im.pos, format("The module '%s' was imported twice by the same file '%s'.", file_, mod));
            return (Node[]).init;
        }

        context.mods[file] = mod;
        string content = readText(file_);
        Lexer l = new Lexer(file, path, content, err, registry);
        Token[] tokens = l.tokenizer();
        check_diagnostic(err);

        Parser p = new Parser(tokens, err, registry, generic, context);
        Program prog = p.parse();
        check_diagnostic(err);
        return prog.body;
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
        mod = ext(filename); // monta o modulo atual com base na posição

        foreach (ImportStmt im; imports)
        {
            string p = path;
            string file = im.file;
            string file_ = p ~ file;
            string filecx = ext(file_);

            if (!exists(file_) && !exists(filecx))
            {
                p = context.cxdir;
                file_ = p ~ file;
                filecx = ext(file_);
                if (!exists(file_) && !exists(filecx))
                {
                    err.error(im.pos, format("Non-existent module '%s'.", filecx));
                    continue;
                }
            }

            if (!exists(filecx))
            {
                // importa o diretório inteiro
                // subdiretórios não são importados por segurança
                DirEntry[] files = dirEntries(file_, SpanMode.shallow).array;
                foreach (DirEntry f; files)
                {
                    if (!f.isFile())
                        continue;
                    
                    filecx = f.name();
                    if (extension(filecx) != ".cx")
                        continue;

                    file = baseName(filecx)[0..$-3];
                    body ~= importFile(file, im, mod, filecx, p);
                }
                continue;
            }
            else
                body ~= importFile(file, im, mod, filecx, p);
        }

        body ~= program.body;
        program.body = body;
    }
}
