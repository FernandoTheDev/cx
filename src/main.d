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
__gshared bool noHeader;

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
	writeln("      --no-header       It will not automatically generate the Cx header.");
	writeln("      --gen-header      It will generate a .h file and a .c file without compiling at the end.");
	writeln("      --cflags      	Pass compilation flags to the C compiler.");
	writeln();
	writeln("Environment:");
	writeln("  CC                    C compiler used to build the output (default: cc)");
	writeln();
	writeln("Examples:");
	writeln("  cx main.cx");
	writeln("  cx main.cx --opt -o main");
	writeln("  cx main.cx --cflags=\"--O2 -o main\"");
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
	{
		writeln(
			"The compiler does not yet support Windows, even though there is a build script and you managed to compile it.");
		return 1;
	}
	
	version (OSX)
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

	bool emitc, opt, dbg, verMessage, helpMessage, genHeader;
	string[] link, cflags;
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
			"no-header", &noHeader,
			"gen-header", &genHeader,
			"cflags", &cflags,
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
	Program program;
	
	try
		program = p.parse();
	catch (Exception e)
	{
		writefln("An internal error occurred in the parser: %s", e.message);
		// writeln(e);
		return 1;
	}

	check_diagnostic(err);

	// faz duas passagens pra resolução completa
	generic.resolve(program);
	generic.resolve(program);
	new TypeResolver(registry).resolve(program);

	program.body = ResolveSymbols.resolve(err, ctx, program.body);
	check_diagnostic(err);

	string fileh = output ~ ".h";
	string filec = output ~ ".c";
	string[2] src = new CodeGen(program, registry, ctx.statics, noHeader, genHeader, fileh, ctx).compile();
	check_diagnostic(err);
	write(filec, src[0]);

	if (genHeader)
	{
		write(fileh, src[1]);
		writefln("Success: two individual files, '%s' and '%s', were generated.", filec, fileh);
		return 0;
	}

	if (emitc)
	{
		writefln("File '%s' generated.", filec);
		return 0;
	}

	string c_compiler = environment.get("CC", "cc");
	string command = format("%s %s %s -o %s %s %s", c_compiler, filec, (opt ? "-O2" : ""), output,
		link.length > 0 ? (link.map!(l => format("-l%s", l).array).join(" ")) : "", cflags.join(" "));
	if (dbg)
		writeln("C Compiler: ", c_compiler);

	auto exec = executeShell(command);
	if (dbg)
		writeln("Command: ", command);
	if (exec.status != 0)
	{
		writeln("An error occurred while compiling the program.");
		writeln(exec.output);
		return exec.status;
	}

	executeShell(format("rm -f %s", filec));
	return 0;
}
