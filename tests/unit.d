// rdmd tests/unit.d
module tests.unit;

import std.format;
import std.stdio;
import std.file;
import std.algorithm;
import std.array;
import std.process;
import std.typecons;
import std.range;
import std.conv;

string escape(string str)
{
    ulong offset;
    string buffer;
    while (offset < str.length)
    {
        char ch = str[offset++];
        if (ch == '\\' && offset < str.length)
        {
            char esc = str[offset];
            switch (esc)
            {
            case 'n':
                buffer ~= '\n';
                offset++;
                continue;
            default:
                break;
            }
        }
        buffer ~= [ch];
    }
    return buffer;
}

struct TestResult
{
    string filename;
    bool ok;
    string err;
    bool ignored;
}

TestResult runTest(string filename)
{
    alias Exec = Tuple!(int, "status", string, "output");
    TestResult res;
    res.filename = filename;

    File content = File(filename, "r");
    string firstLine = content.byLine().front.idup;
    content.close();

    bool fromCode   = firstLine.length > 3 && firstLine[0 .. 3] == "//#";
    bool fromOutput = firstLine.length > 3 && firstLine[0 .. 3] == "//!";

    if (!fromCode && !fromOutput)
    {
        res.ignored = true;
        return res;
    }

    firstLine = firstLine[4 .. $];

    string cFile  = filename ~ ".gen.c";
    string binFile = filename ~ ".bin";

    // 1) Cx -> C
    Exec cxComp = executeShell(format("./cx %s > %s", filename, cFile));
    if (cxComp.status != 0)
    {
        res.ok  = false;
        res.err = "Falha no compilador Cx:\n" ~ cxComp.output;
        remove_if_exists(cFile);
        return res;
    }

    // 2) C -> binário (C99 puro, mesmo alvo de portabilidade do projeto)
    string llvm;
    if (filename.length > 13 && filename[9..13] == "llvm")
        llvm = "-lLLVM-22";
    Exec cComp = executeShell(format("cc %s -std=c99 %s -o %s", llvm, cFile, binFile));
    if (cComp.status != 0)
    {
        res.ok  = false;
        res.err = "Falha ao compilar o C gerado:\n" ~ cComp.output ~ "\n\n--- C gerado ---\n" ~ readTextSafe(cFile);
        remove_if_exists(cFile);
        remove_if_exists(binFile);
        return res;
    }

    // 3) roda o binário
    Exec run = executeShell(format("./%s", binFile));
    int code = run.status;
    string output = run.output;

    res.ok = true;

    if (fromCode)
    {
        int expected = to!int(firstLine);
        if (expected != code)
        {
            res.ok  = false;
            res.err = format("Código esperado '%d', recebido '%d'.", expected, code);
        }
    }
    else if (fromOutput)
    {
        string expected = escape(firstLine);
        if (output != expected)
        {
            res.ok  = false;
            res.err = format("Saída esperada '%s', recebida '%s'.", expected, output);
        }
    }

    remove_if_exists(cFile);
    remove_if_exists(binFile);

    return res;
}

void remove_if_exists(string path)
{
    if (exists(path))
        remove(path);
}

string readTextSafe(string path)
{
    if (!exists(path))
        return "(arquivo nao encontrado)";
    return readText(path);
}

void main()
{
    string folder = "examples";
    ulong sucesso, erros, ignorados;

    DirEntry[] dir = dirEntries(folder, SpanMode.depth)
        .filter!(x => x.name.endsWith(".cx"))
        .array
        .sort!((a, b) => a.name < b.name)
        .array;

    writeln("=== Cx ===");
    foreach (DirEntry key; dir)
    {
        TestResult res = runTest(key.name);
        if (res.ignored)
        {
            writefln("  IGNORADO  %s", res.filename);
            ignorados++;
        }
        else if (res.ok)
        {
            writefln("  SUCESSO   %s", res.filename);
            sucesso++;
        }
        else
        {
            writefln("  ERRO      %s", res.filename);
            writeln("            ", res.err);
            erros++;
        }
    }

    writeln();
    writefln("SUCESSOS:  %d", sucesso);
    writefln("ERROS:     %d", erros);
    writefln("IGNORADOS: %d", ignorados);
    writefln("TOTAL:     %d", sucesso + erros + ignorados);
}
