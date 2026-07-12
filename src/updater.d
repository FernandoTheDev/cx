module updater;

import std.file : mkdirRecurse, rmdirRecurse, exists, rename, copy, isDir, isFile, remove, dirEntries, SpanMode;
import std.json : parseJSON, JSONValue, JSONException;
import std.process : executeShell, environment;
import std.stdio : writeln, writefln, stderr;
import std.string : startsWith, endsWith;
import std.path : buildPath, baseName;
import std.random : uniform;
import std.format : format;
import env;

int runUpdate()
{
    writeln("Checking for updates...");

    string repo = GITHUB_REPO;
    if (repo.startsWith("https://github.com/"))
        repo = repo[19 .. $];
    if (repo.endsWith(".git"))
        repo = repo[0 .. $ - 4];

    string apiUrl = format("https://api.github.com/repos/%s/releases/latest", repo);

    auto fetchResult = executeShell(format("curl -sL '%s'", apiUrl));
    if (fetchResult.status != 0)
    {
        stderr.writefln("Failed to fetch release information.");
        return 1;
    }

    JSONValue json;
    try
        json = parseJSON(fetchResult.output);
    catch (JSONException e)
    {
        stderr.writefln("Failed to parse GitHub API response: %s", e.msg);
        return 1;
    }

    if ("tag_name" !in json)
    {
        stderr.writefln("Unexpected API response (missing tag_name). Rate limited?");
        return 1;
    }

    string tagName = json["tag_name"].str;
    string remoteVersion = tagName.startsWith("v") ? tagName[1 .. $] : tagName;

    if (remoteVersion == COMPILER_VERSION)
    {
        writefln("You are already on the latest version (%s).", COMPILER_VERSION);
        return 0;
    }

    writefln("New version available: %s (current: %s)", remoteVersion, COMPILER_VERSION);

    if ("assets" !in json || json["assets"].array.length == 0)
    {
        stderr.writefln("No assets found in the latest release.");
        return 1;
    }

    string downloadUrl;
    string assetName;

    foreach (asset; json["assets"].array)
    {
        string name = asset["name"].str;
        if (name.endsWith(".zip"))
        {
            downloadUrl = asset["browser_download_url"].str;
            assetName = name;
            break;
        }
    }

    if (downloadUrl.length == 0)
    {
        stderr.writefln("Could not find a .zip release asset in the latest release.");
        return 1;
    }

    string home = environment.get("HOME", "");
    if (home.length == 0)
    {
        stderr.writefln("Could not determine HOME directory.");
        return 1;
    }

    string cxHome = buildPath(home, ".cx");
    string tmpDir = buildPath(cxHome, format(".update-tmp-%s", uniform(1000, 9999)));
    mkdirRecurse(tmpDir);

    scope (exit)
        if (exists(tmpDir))
            rmdirRecurse(tmpDir);
    
    string tarPath = buildPath(tmpDir, assetName);
    writefln("Downloading %s...", assetName);
    auto dlResult = executeShell(format("curl -sL '%s' -o '%s'", downloadUrl, tarPath));
    if (dlResult.status != 0 || !exists(tarPath))
    {
        stderr.writefln("Failed to download the update.");
        return 1;
    }

    writefln("Extracting...");
    auto extractResult = executeShell(format("unzip -q '%s' -d '%s'", tarPath, tmpDir));
    if (extractResult.status != 0)
    {
        stderr.writefln("Failed to extract the update.");
        return 1;
    }

    string newBin;
    string newStd;

    foreach (entry; dirEntries(tmpDir, SpanMode.depth))
    {
        if (entry.isFile && baseName(entry.name) == "cx")
            newBin = entry.name;
        if (entry.isDir && baseName(entry.name) == "std")
            newStd = entry.name;
    }

    if (newBin.length == 0 || newStd.length == 0)
    {
        stderr.writefln("Could not find 'cx' binary or 'std' directory in the downloaded release.");
        return 1;
    }

    string localBinDir = buildPath(home, ".local", "bin");
    string currentBin = buildPath(localBinDir, "cx");
    string currentStd = buildPath(cxHome, "std");
    string tmpBinInDest = buildPath(localBinDir, ".cx-new-bin");
    string tmpStdInDest = buildPath(cxHome, ".std-new");
    string backupStd = buildPath(cxHome, ".std-old");
    string backupBin = buildPath(localBinDir, ".cx-old-bin");

    bool binSwapped = false;

    try
    {
        mkdirRecurse(localBinDir);
        copy(newBin, tmpBinInDest);
        executeShell(format("chmod +x '%s'", tmpBinInDest));

        // Backup do binário atual ANTES do swap, pra permitir rollback real
        bool hadOldBin = exists(currentBin);
        if (hadOldBin)
        {
            if (exists(backupBin))
                remove(backupBin);
            rename(currentBin, backupBin);
        }
        rename(tmpBinInDest, currentBin); // Atomic swap
        binSwapped = true;

        // Atualizar Stdlib
        if (exists(tmpStdInDest))
            rmdirRecurse(tmpStdInDest);
        executeShell(format("cp -r '%s' '%s'", newStd, tmpStdInDest));

        if (exists(currentStd))
        {
            if (exists(backupStd))
                rmdirRecurse(backupStd);
            rename(currentStd, backupStd);
        }
        rename(tmpStdInDest, currentStd);

        // Sucesso: limpa os backups
        if (exists(backupStd))
            rmdirRecurse(backupStd);
        if (exists(backupBin))
            remove(backupBin);

        writefln("Successfully updated to version %s!", remoteVersion);
    }
    catch (Exception e)
    {
        stderr.writefln("An error occurred while installing the update: %s", e.msg);

        // Rollback do binário
        if (binSwapped && exists(backupBin))
        {
            if (exists(currentBin))
                remove(currentBin);
            rename(backupBin, currentBin);
        }
        else if (exists(tmpBinInDest))
            remove(tmpBinInDest);

        // Rollback da stdlib
        if (exists(tmpStdInDest))
            rmdirRecurse(tmpStdInDest);
        if (exists(backupStd))
        {
            if (!exists(currentStd))
                rename(backupStd, currentStd);
            else
                rmdirRecurse(backupStd);
        }

        return 1;
    }

    return 0;
}
