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
import std.string;

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

// Descobre a major version do LLVM instalado no sistema, na ordem:
// 1) variável de ambiente LLVM_LINK_VERSION (override manual, útil em CI)
// 2) `llvm-config --version`
// 3) fallback vazio (nenhuma flag -L é passada, deixa o cx/gcc resolverem sozinhos)
string detectLlvmLinkFlag()
{
    string envOverride = environment.get("LLVM_LINK_VERSION", "");
    if (envOverride.length > 0)
        return format("-L LLVM-%s", envOverride);

    auto res = executeShell("llvm-config --version");
    if (res.status == 0)
    {
        string ver = res.output.strip();
        auto dot = ver.indexOf('.');
        string major = dot > 0 ? ver[0 .. dot] : ver;
        if (major.length > 0)
            return format("-L LLVM-%s", major);
    }

    return "";
}

TestResult runTest(string filename, string llvmLinkFlag)
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
    string llvm;
    if (filename.length > 13 && filename[9..13] == "llvm")
        llvm = llvmLinkFlag;
    Exec cxComp = executeShell(format("cx %s --output %s %s", filename, binFile, llvm));
    if (cxComp.status != 0)
    {
        res.ok  = false;
        res.err = "Falha no compilador Cx:\n" ~ cxComp.output;
        remove_if_exists(cFile);
        return res;
    }

    // 2) roda o binário
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

int main()
{
    string folder = "examples";
    ulong sucesso, erros, ignorados;

    string llvmLinkFlag = detectLlvmLinkFlag();
    if (llvmLinkFlag.length > 0)
        writefln("=== LLVM link flag detectada: %s ===", llvmLinkFlag);
    else
        writeln("=== Aviso: não foi possível detectar versão do LLVM via llvm-config; testes llvm*.cx podem falhar ===");

    DirEntry[] dir = dirEntries(folder, SpanMode.depth)
        .filter!(x => x.name.endsWith(".cx"))
        .array
        .sort!((a, b) => a.name < b.name)
        .array;

    writeln("=== Cx ===");
    foreach (DirEntry key; dir)
    {
        TestResult res = runTest(key.name, llvmLinkFlag);
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

    return erros ? 1 : 0;
}
