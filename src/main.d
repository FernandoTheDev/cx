module main;

import backend.codegen;
import frontend;
import errors;
import utils;
import env;

import std.path : dirName, baseName, extension;
import core.stdc.stdlib : exit;
import std.stdio : writeln, writefln;
import std.algorithm;
import std.exception;
import std.process;
import std.format;
import std.getopt;
import std.array;
import std.file;

__gshared Generic generic;

pragma(inline, true)
void check_diagnostic(Diagnostics d)
{
	if (d.report())
		exit(1);
}

pragma(inline, true)
void showHelp()
{
	writeln("Usage: cx [options] <file.cx>");
	writeln();
	writeln("Options:");
	writeln(
		"  -o, --output <name>   Set the output binary name (default: input filename without .cx)");
	writeln("  -L, --link <lib>      Link an external library (can be used multiple times)");
	writeln("      --opt             Enable optimizations (-O2 in the underlying C compiler)");
	writeln("      --emit-c          Only emit the generated .c file, without compiling it");
	writeln("  -d, --debug           Print debug information, such as the C compiler in use");
	writeln("  -h, --help            Show this help message and exit");
	writeln("  -v, --version         Show the compiler version and exit");
	writeln();
	writeln("Environment:");
	writeln("  CC                    C compiler used to build the output (default: cc)");
	writeln();
	writeln("Examples:");
	writeln("  cx main.cx");
	writeln("  cx main.cx --opt -o main");
	writeln("  cx main.cx --emit-c");
	writeln("  cx main.cx -L m -L pthread -o app");
	writeln("  CC=x86_64-w64-mingw32-gcc cx main.cx -o main.exe");
}

pragma(inline, true)
void showVersion()
{
	writefln("Cx Compiler - Version (%s)", COMPILER_VERSION);
}

int main(string[] argv)
{
	string stdDir;
	string OS;

	version (Windows)
	    OS = "windows";
	else version (OSX)
	    OS = "macos";
	else version (linux)
	    OS = "linux";
	else version (Posix)
	    OS = "unix";
	else
	    OS = "unknown";

	if (OS == "unknown")
	{
		writefln("Unable to detect your operating system; please create an issue in the GitHub repository: '%s'", 
			GITHUB_REPO);
		return 0;
	}

	if (OS != "windows")
	{
		string home = environment.get("HOME", "");
		stdDir = home ~ "/" ~ ".cx/";
		if (!home || !exists(stdDir))
		{
			writefln("An error occurred while validating the compiler installation.");
			writefln("Some folders may be missing; check if this path is valid: '%s'.", stdDir);
			writefln(
				"If it does not exist, then an error occurred while installing the compiler on your system.");
			return 0;
		}
	}

	bool emitc, opt, dbg, verMessage, helpMessage;
	string[] link;
	string output, target;

	try
		getopt(argv,
			"opt", &opt,
			"version|v", &verMessage,
			"help|h", &helpMessage,
			"debug|d", &dbg,
			"emit-c", &emitc,
			"link|L", &link,
			"output|o", &output,
			"target", &target,
		);
	catch (GetOptException e)
	{
		writefln("Invalid flag '%s'.", e.message[20 .. $]);
		return 1;
	}

	if (verMessage)
	{
		showVersion();
		return 0;
	}

	if (helpMessage)
	{
		showHelp();
		return 0;
	}

	if (target == "")
	{
		version (linux)
			target = "linux";
		else version (Windows)
			target = "windows";
		else version (OSX)
			target = "macos";
		else version (Unix)
			target = "unix";
		else
			target = "unknown";
	}

	cx_enforce(argv.length == 2, "The compiler expects at least one file.");
	string filename = argv[1];
	cx_enforce(extension(filename) == ".cx", "The file is not a valid .cx file.");
	cx_enforce(exists(filename), format("The file '%s' does not exist.", filename));

	string dir = dirName(filename) ~ "/";
	string content = readText(filename);
	string file = baseName(filename);
	output = output == "" ? file[0 .. $ - 3] : output;

	Diagnostics err = new Diagnostics;
	TypeRegistry registry = new TypeRegistry;
	Lexer l = new Lexer(file, dir, content, err, registry);
	Token[] tokens = l.tokenizer();
	check_diagnostic(err);

	ImportResolverContext* ctx = new ImportResolverContext(stdDir);
	generic = new Generic(registry);
	Parser p = new Parser(tokens, err, registry, generic, ctx);
	Program program = p.parse();
	check_diagnostic(err);

	new ImportResolver(ctx, program, err, registry, generic).resolve();
	check_diagnostic(err);

	// faz duas passagens pra resolução completa
	generic.resolve(program);
	generic.resolve(program);
	new TypeResolver(registry).resolve(program);

	program.body = ResolveSymbols.resolve(err, ctx, program.body);
	check_diagnostic(err);

	string src = new CodeGen(program, registry, ctx.statics).compile();
	string filec = output ~ ".c";
	write(filec, src);

	if (emitc)
	{
		writefln("File '%s' generated.", filec);
		return 0;
	}

	string c_compiler = environment.get("CC", "cc");
	string command = format("%s %s -O%d -o %s %s", c_compiler, filec, opt ? 2 : 0, output,
		link.length > 0 ? (link.map!(l => format("-l%s", l).array).join(" ")) : "");
	if (dbg)
		writeln("C Compiler: ", c_compiler);

	int code_cc = executeShell(command).status;
	if (code_cc != 0)
	{
		writeln("An error occurred while compiling the program.");
		writeln("Command: ", command);
		writeln("Compiler code: ", code_cc);
		return 1;
	}

	executeShell(format("rm -f %s", filec));
	return 0;
}
