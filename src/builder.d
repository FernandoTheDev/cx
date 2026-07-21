module builder;

import main : CXArgs, compile;
import utils;


import std.stdio : writeln, writefln, stdout, readln, dwrite = write;
import std.process;
import std.format;
import std.string;
import std.json;
import std.file;
import std.path;
import std.file;

enum ERROR_MESSAGE = "The 'compile' command must be used within cx projects.";
const string maincx = `import std.io;

int main() {
    printf("Hello World!\n");
    return 0;
}
`;

const string cxjson = `{
    "name": "%s",
    "output": "%s"
}
`;

string getInput(string message, string fallback)
{
    dwrite(format("%s (default: %s): ", message, fallback));
    stdout.flush();
    string input = readln().strip();
    return input == "" ? fallback : input;
}

int runBuild() 
{
    /*
        src/main.cx
        cx.json
    */
    string name = getInput("Project name", "cx-project");
    string binary = getInput("Output file", "main");

    if (!exists("src"))
    {
        mkdir("src");
        write("./src/main.cx", maincx);
    }

    if (!exists("cx.json"))
        write("./cx.json", format(cxjson, name, binary));

    writeln("Done!");

    return 0;
}

bool keyExists(string key, JSONValue json)
{
    try
        auto _ = json[key];
    catch(Exception e)
        return false;
    return true;
}

T getValue(T)(string key, JSONValue json, T fallback)
{
    if (!keyExists(key, json))
        return fallback;

    T val;
    try
    {
        static if (is(T == string))
            val = json[key].str;
        else static if (is(T == bool))
            val = json[key].boolean;
        else
            static assert(0, "Error: " ~ T.stringof);
    }
    catch (Exception e)
        return fallback;
 
    return val;
}

int runCompile(bool isRun, ref CXArgs args)
{
    string main = "./src/main.cx";
    string fileJson = "./cx.json";

	cx_enforce(exists(main) && exists(fileJson), ERROR_MESSAGE);
	cx_enforce(isFile(main) && isFile(fileJson), ERROR_MESSAGE); // 2Auth

    string jsonContent = readText(fileJson);
    JSONValue json = parseJSON(jsonContent);
    
    string binary = getValue!string("output", json, "main");
    args.output = binary;

	int _ = compile(main, args);
	if (!isRun) return _;

	cx_enforce(exists(binary), "An error occurred while compiling the project.");
	auto exec = executeShell("./" ~ binary);
	dwrite(exec.output);

	return exec.status;
}
