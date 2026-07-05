module main;

import backend.codegen;
import frontend;
import errors;
import utils;

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

int main(string[] argv)
{
	bool emitc, opt, dbg;
	string[] link;
	string output;

	getopt(argv,
		"opt", &opt,
		"debug|d", &dbg,
		"emit-c", &emitc,
		"link|L", &link,
		"output|o", &output,
	);

	cx_enforce(argv.length == 2, "The compiler expects at least one file.");
	string filename = argv[1];
	cx_enforce(extension(filename) == ".cx", "The file is not a valid .cx file.");
	cx_enforce(exists(filename), format("The file '%s' does not exist.", filename));

	string dir = dirName(filename) ~ "/";
	string content = readText(filename);
	string file = baseName(filename);
	output = output == "" ? file[0..$-3] : output;

	Diagnostics err = new Diagnostics;
	TypeRegistry registry = new TypeRegistry;
	Lexer l = new Lexer(file, dir, content, err, registry);
	Token[] tokens = l.tokenizer();
	check_diagnostic(err);

	ImportResolverContext* ctx = new ImportResolverContext();
	generic = new Generic(registry);
	Parser p = new Parser(tokens, err, registry, generic, ctx);
	Program program = p.parse();
	check_diagnostic(err);

	new ImportResolver(ctx, program, err, registry, generic).resolve();
	check_diagnostic(err);

	generic.resolve(program);
	generic.resolve(program);
	new TypeResolver(registry).resolve(program);

	string src = new CodeGen(program, registry, ctx.statics).compile();
	string filec = output ~ ".c";
	write(filec, src);

	if (emitc)
	{
		writefln("File '%s' generated.", filec);
		return 0;
	}

	string c_compiler = environment.get("CC") == "" ? "cc" : environment.get("CC");
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
