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

// Detects the major LLVM version installed on the system, in order:
// 1) LLVM_LINK_VERSION environment variable (manual override, useful in CI)
// 2) `llvm-config --version`
// 3) empty fallback (no -L flag passed, let cx/gcc resolve it on their own)
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
        res.err = "Cx compiler failed:\n" ~ cxComp.output;
        remove_if_exists(cFile);
        return res;
    }

    // 2) run the binary
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
            res.err = format("Expected exit code '%d', got '%d'.", expected, code);
        }
    }
    else if (fromOutput)
    {
        string expected = escape(firstLine);
        if (output != expected)
        {
            res.ok  = false;
            res.err = format("Expected output '%s', got '%s'.", expected, output);
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
        return "(file not found)";
    return readText(path);
}

int main()
{
    string folder = "examples";
    ulong sucesso, erros, ignorados;

    string llvmLinkFlag = detectLlvmLinkFlag();
    if (llvmLinkFlag.length > 0)
        writefln("=== Detected LLVM link flag: %s ===", llvmLinkFlag);
    else
        writeln("=== Warning: could not detect LLVM version via llvm-config; llvm*.cx tests may fail ===");

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
            writefln("  IGNORED   %s", res.filename);
            ignorados++;
        }
        else if (res.ok)
        {
            writefln("  PASS      %s", res.filename);
            sucesso++;
        }
        else
        {
            writefln("  FAIL      %s", res.filename);
            writeln("            ", res.err);
            erros++;
        }
    }

    writeln();
    writefln("PASSED:  %d", sucesso);
    writefln("FAILED:  %d", erros);
    writefln("IGNORED: %d", ignorados);
    writefln("TOTAL:   %d", sucesso + erros + ignorados);

    return erros ? 1 : 0;
}
