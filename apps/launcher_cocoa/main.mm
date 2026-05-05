#import <Cocoa/Cocoa.h>
#include <ApplicationServices/ApplicationServices.h>

#include <components/debug/debugging.hpp>
#include <components/debug/debuglog.hpp>
#include <components/files/configurationmanager.hpp>
#include <components/settings/settings.hpp>
#include <components/settings/windowmode.hpp>
#include <components/sceneutil/lightingmethod.hpp>
#include <components/sdlutil/vsyncmode.hpp>

#include <tinyxml.h>

#include <boost/program_options/options_description.hpp>
#include <boost/program_options/variables_map.hpp>

#include <algorithm>
#include <array>
#include <cstdio>
#include <cfloat>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <utility>
#include <vector>

namespace
{
    namespace bpo = boost::program_options;

    std::string toLower(std::string value);
    bool hasExtension(const std::filesystem::path& path, const char* extension);

    void initializeConfiguration(Files::ConfigurationManager& cfgMgr)
    {
        bpo::options_description desc("Launcher");
        Files::ConfigurationManager::addCommonOptions(desc);
        bpo::variables_map variables;
        cfgMgr.readConfiguration(variables, desc, true);
    }

    std::string trim(const std::string& value)
    {
        std::size_t begin = 0;
        while (begin < value.size() && std::isspace(static_cast<unsigned char>(value[begin])))
            ++begin;
        std::size_t end = value.size();
        while (end > begin && std::isspace(static_cast<unsigned char>(value[end - 1])))
            --end;
        return value.substr(begin, end - begin);
    }

    bool startsWith(const std::string& value, const char* prefix)
    {
        const std::size_t length = std::char_traits<char>::length(prefix);
        return value.size() >= length && value.compare(0, length, prefix) == 0;
    }

    std::string unquote(std::string value)
    {
        value = trim(value);
        if (value.size() >= 2 && value.front() == '"' && value.back() == '"')
            return value.substr(1, value.size() - 2);
        return value;
    }

    std::string quote(const std::string& value)
    {
        return "\"" + value + "\"";
    }

    std::vector<std::string> splitLines(const std::string& value)
    {
        std::vector<std::string> result;
        std::istringstream stream(value);
        std::string line;
        while (std::getline(stream, line))
        {
            line = trim(line);
            if (!line.empty())
                result.push_back(line);
        }
        return result;
    }

    std::string joinLines(const std::vector<std::string>& values)
    {
        std::ostringstream stream;
        for (std::size_t i = 0; i < values.size(); ++i)
        {
            if (i != 0)
                stream << '\n';
            stream << values[i];
        }
        return stream.str();
    }

    NSString* toNSString(const std::string& value)
    {
        return [NSString stringWithUTF8String:value.c_str()];
    }

    std::string fromNSString(NSString* value)
    {
        if (!value)
            return std::string();
        const char* chars = [value UTF8String];
        return chars ? std::string(chars) : std::string();
    }

    std::string pathToString(const std::filesystem::path& path)
    {
        return path.string();
    }

    NSString* readTextView(NSTextView* view)
    {
        return [[view textStorage] string];
    }

    std::string sanitizePathComponent(const std::string& value)
    {
        std::string result;
        result.reserve(value.size());
        for (std::size_t i = 0; i < value.size(); ++i)
        {
            const unsigned char c = static_cast<unsigned char>(value[i]);
            if (std::isalnum(c) || c == '-' || c == '_' || c == ' ')
                result.push_back(static_cast<char>(c));
            else
                result.push_back('_');
        }

        result = trim(result);
        while (!result.empty() && (result.back() == '.' || result.back() == ' '))
            result.pop_back();

        return result.empty() ? "mod" : result;
    }

    std::filesystem::path uniquePath(const std::filesystem::path& base)
    {
        if (!std::filesystem::exists(base))
            return base;

        for (int suffix = 2; suffix < 10000; ++suffix)
        {
            std::ostringstream stream;
            stream << base.filename().string() << "-" << suffix;
            std::filesystem::path candidate = base.parent_path() / stream.str();
            if (!std::filesystem::exists(candidate))
                return candidate;
        }

        return base;
    }

    bool hasAnyKnownDataEntries(const std::filesystem::path& dir)
    {
        static const char* const directories[] = {
            "bookart", "fonts", "icons", "meshes", "music", "shaders", "sound", "splash", "textures", "video"
        };

        std::error_code ec;
        for (std::filesystem::directory_iterator it(dir, ec); !ec && it != std::filesystem::directory_iterator();
             it.increment(ec))
        {
            const std::filesystem::path path = it->path();
            if (it->is_directory(ec))
            {
                const std::string lower = toLower(path.filename().string());
                for (std::size_t i = 0; i < sizeof(directories) / sizeof(directories[0]); ++i)
                {
                    if (lower == directories[i])
                        return true;
                }
            }
            else if (it->is_regular_file(ec))
            {
                if (hasExtension(path, ".esm") || hasExtension(path, ".esp") || hasExtension(path, ".omwgame")
                    || hasExtension(path, ".omwaddon") || hasExtension(path, ".bsa"))
                {
                    return true;
                }
            }
        }
        return false;
    }

    std::filesystem::path resolveExtractedDataPath(const std::filesystem::path& dir)
    {
        if (hasAnyKnownDataEntries(dir))
            return dir;

        std::error_code ec;
        std::vector<std::filesystem::path> subdirs;
        for (std::filesystem::directory_iterator it(dir, ec); !ec && it != std::filesystem::directory_iterator();
             it.increment(ec))
        {
            if (it->is_directory(ec))
                subdirs.push_back(it->path());
        }

        if (subdirs.size() == 1 && hasAnyKnownDataEntries(subdirs[0]))
            return subdirs[0];

        return dir;
    }

    void selectPopupByValue(NSPopUpButton* popup, const std::string& value, NSInteger fallbackIndex = 0)
    {
        if (!popup)
            return;
        if (!value.empty() && [popup itemWithTitle:toNSString(value)] != nil)
            [popup selectItemWithTitle:toNSString(value)];
        else
            [popup selectItemAtIndex:fallbackIndex];
    }

    struct OpenMWUserConfig
    {
        std::vector<std::string> preservedLines;
        std::vector<std::string> dataDirs;
        std::vector<std::string> archives;
        std::vector<std::string> contentFiles;

        void load(const std::filesystem::path& path)
        {
            preservedLines.clear();
            dataDirs.clear();
            archives.clear();
            contentFiles.clear();

            std::ifstream stream(path);
            if (!stream)
                return;

            std::string line;
            while (std::getline(stream, line))
            {
                const std::string trimmed = trim(line);
                if (startsWith(trimmed, "data="))
                    dataDirs.push_back(unquote(trimmed.substr(5)));
                else if (startsWith(trimmed, "fallback-archive="))
                    archives.push_back(unquote(trimmed.substr(17)));
                else if (startsWith(trimmed, "content="))
                    contentFiles.push_back(unquote(trimmed.substr(8)));
                else
                    preservedLines.push_back(line);
            }
        }

        bool save(const std::filesystem::path& path) const
        {
            std::ofstream stream(path, std::ios::out | std::ios::trunc);
            if (!stream)
                return false;

            for (std::vector<std::string>::const_iterator it = preservedLines.begin(); it != preservedLines.end(); ++it)
                stream << *it << '\n';

            if (!preservedLines.empty())
                stream << '\n';

            for (std::vector<std::string>::const_iterator it = dataDirs.begin(); it != dataDirs.end(); ++it)
                stream << "data=" << quote(*it) << '\n';
            for (std::vector<std::string>::const_iterator it = archives.begin(); it != archives.end(); ++it)
                stream << "fallback-archive=" << *it << '\n';
            for (std::vector<std::string>::const_iterator it = contentFiles.begin(); it != contentFiles.end(); ++it)
                stream << "content=" << *it << '\n';

            return true;
        }
    };

    struct LauncherModel
    {
        std::vector<std::string> dataDirs;
        std::vector<std::string> archives;
        std::vector<std::string> contentFiles;
        std::string importerIni;
        int resolutionX = 800;
        int resolutionY = 600;
        int screen = 0;
        Settings::WindowMode windowMode = Settings::WindowMode::Windowed;
        bool windowBorder = true;
        SDLUtil::VSyncMode vsyncMode = SDLUtil::Enabled;
        int frameRateLimit = 60;
        int antialiasing = 0;
        int anisotropy = 4;
        int lightingMethod = 1;
        float viewingDistance = 8192.f * 4.f;
        float objectPagingMinSize = 0.09f;
        int waterReflectionDetail = 0;
        float postProcessExposureSpeed = 1.f;
        float skyBlendingStart = 0.1f;
        float shadowDistance = 0.f;
        float shadowFadeStart = 0.f;
        int shadowMapResolution = 1024;
        std::string textureMagFilter = "linear";
        std::string textureMinFilter = "linear";
        std::string textureMipmap = "nearest";
        std::string shadowComputeSceneBounds = "bounds";
        std::string threadingMode;
        bool softParticles = false;
        bool radialFog = false;
        bool exponentialFog = false;
        bool skyBlending = false;
        bool distantTerrain = false;
        bool objectPaging = true;
        bool objectPagingActiveGrid = true;
        bool groundcover = false;
        bool weatherParticleOcclusion = false;
        bool postProcessing = false;
        bool transparentPostpass = false;
        bool shadows = false;
        bool actorShadows = false;
        bool playerShadows = false;
        bool terrainShadows = false;
        bool objectShadows = false;
        bool indoorShadows = false;
        bool waterShader = false;
        bool waterRefraction = false;
        bool waterSunlightScattering = false;
        bool waterWobblyShores = false;
        bool skipMenu = false;
    };

    struct InstalledModInfo
    {
        std::string name;
        std::string rootPath;
        std::string dataPath;
        bool active = false;
    };

    struct FomodFileEntry
    {
        std::string source;
        std::string destination;
        int priority = 0;
        bool isFolder = false;
    };

    struct FomodFlag
    {
        std::string name;
        std::string value;
    };

    struct FomodDependency
    {
        enum Type
        {
            Type_None,
            Type_And,
            Type_Or,
            Type_Flag,
            Type_File,
            Type_Game
        };

        Type type = Type_None;
        std::string name;
        std::string value;
        std::string state;
        std::vector<FomodDependency> children;
    };

    struct FomodPlugin
    {
        std::string name;
        std::string description;
        std::vector<FomodFileEntry> files;
        std::vector<FomodFlag> flags;
    };

    struct FomodGroup
    {
        std::string name;
        std::string type;
        std::vector<FomodPlugin> plugins;
    };

    struct FomodStep
    {
        std::string name;
        FomodDependency visible;
        std::vector<FomodGroup> groups;
    };

    struct FomodConditionalPattern
    {
        FomodDependency dependencies;
        std::vector<FomodFileEntry> files;
    };

    struct FomodConfig
    {
        std::string moduleName;
        std::vector<FomodFileEntry> requiredFiles;
        std::vector<FomodStep> steps;
        std::vector<FomodConditionalPattern> conditionalPatterns;
    };

    struct FomodInstallState
    {
        std::map<std::string, std::string> flags;
        std::set<std::string> availableFiles;
        std::set<std::string> activeFiles;
    };

    std::string normalizeArchiveRelativePath(std::string value)
    {
        std::replace(value.begin(), value.end(), '\\', '/');
        while (startsWith(value, "./"))
            value.erase(0, 2);
        while (!value.empty() && value.front() == '/')
            value.erase(value.begin());
        return value;
    }

    std::filesystem::path normalizeInstallDestination(const std::string& destination)
    {
        std::string normalized = normalizeArchiveRelativePath(destination);
        std::vector<std::string> components;
        std::stringstream stream(normalized);
        std::string segment;
        while (std::getline(stream, segment, '/'))
        {
            segment = trim(segment);
            if (segment.empty() || segment == ".")
                continue;
            components.push_back(segment);
        }

        if (!components.empty())
        {
            const std::string first = toLower(components.front());
            if (first == "data files" || first == "data")
                components.erase(components.begin());
        }

        std::filesystem::path result;
        for (std::size_t i = 0; i < components.size(); ++i)
            result /= components[i];
        return result;
    }

    const TiXmlElement* firstChildElementNamed(const TiXmlElement* parent, const char* name)
    {
        return parent ? parent->FirstChildElement(name) : 0;
    }

    std::string xmlAttribute(const TiXmlElement* element, const char* name)
    {
        const char* value = element ? element->Attribute(name) : 0;
        return value ? value : "";
    }

    std::string xmlText(const TiXmlElement* element)
    {
        if (!element || !element->GetText())
            return "";
        return trim(element->GetText());
    }

    void parseFomodFiles(const TiXmlElement* parent, std::vector<FomodFileEntry>& output)
    {
        if (!parent)
            return;

        for (const TiXmlElement* child = parent->FirstChildElement(); child; child = child->NextSiblingElement())
        {
            const std::string tag = toLower(child->Value());
            if (tag != "file" && tag != "folder")
                continue;

            FomodFileEntry entry;
            entry.isFolder = tag == "folder";
            entry.source = normalizeArchiveRelativePath(xmlAttribute(child, "source"));
            entry.destination = xmlAttribute(child, "destination");
            entry.priority = atoi(xmlAttribute(child, "priority").c_str());
            if (!entry.source.empty())
                output.push_back(entry);
        }
    }

    FomodDependency parseFomodDependencyNode(const TiXmlElement* element)
    {
        FomodDependency dependency;
        if (!element)
            return dependency;

        const std::string tag = toLower(element->Value());
        if (tag == "dependencies" || tag == "moduledependencies" || tag == "visible")
        {
            const std::string op = toLower(xmlAttribute(element, "operator"));
            dependency.type = op == "or" ? FomodDependency::Type_Or : FomodDependency::Type_And;
            for (const TiXmlElement* child = element->FirstChildElement(); child; child = child->NextSiblingElement())
                dependency.children.push_back(parseFomodDependencyNode(child));
        }
        else if (tag == "flagdependency")
        {
            dependency.type = FomodDependency::Type_Flag;
            dependency.name = xmlAttribute(element, "flag");
            if (dependency.name.empty())
                dependency.name = xmlAttribute(element, "name");
            dependency.value = xmlAttribute(element, "value");
        }
        else if (tag == "filedependency")
        {
            dependency.type = FomodDependency::Type_File;
            dependency.name = xmlAttribute(element, "file");
            dependency.state = toLower(xmlAttribute(element, "state"));
        }
        else if (tag == "gamedependency")
        {
            dependency.type = FomodDependency::Type_Game;
            dependency.name = xmlAttribute(element, "version");
        }
        return dependency;
    }

    FomodConfig parseFomodConfig(const std::filesystem::path& configPath)
    {
        FomodConfig config;
        const std::string configPathString = pathToString(configPath);
        TiXmlDocument document(configPathString.c_str());
        if (!document.LoadFile())
            return config;

        const TiXmlElement* root = document.RootElement();
        if (!root)
            return config;

        config.moduleName = xmlText(firstChildElementNamed(root, "moduleName"));
        parseFomodFiles(firstChildElementNamed(root, "requiredInstallFiles"), config.requiredFiles);

        const TiXmlElement* installSteps = firstChildElementNamed(root, "installSteps");
        if (installSteps)
        {
            for (const TiXmlElement* stepElement = installSteps->FirstChildElement("installStep"); stepElement;
                 stepElement = stepElement->NextSiblingElement("installStep"))
            {
                FomodStep step;
                step.name = xmlAttribute(stepElement, "name");
                step.visible = parseFomodDependencyNode(firstChildElementNamed(stepElement, "visible"));

                const TiXmlElement* groups = firstChildElementNamed(stepElement, "optionalFileGroups");
                if (groups)
                {
                    for (const TiXmlElement* groupElement = groups->FirstChildElement("group"); groupElement;
                         groupElement = groupElement->NextSiblingElement("group"))
                    {
                        FomodGroup group;
                        group.name = xmlAttribute(groupElement, "name");
                        group.type = toLower(xmlAttribute(groupElement, "type"));

                        const TiXmlElement* plugins = firstChildElementNamed(groupElement, "plugins");
                        if (plugins)
                        {
                            for (const TiXmlElement* pluginElement = plugins->FirstChildElement("plugin"); pluginElement;
                                 pluginElement = pluginElement->NextSiblingElement("plugin"))
                            {
                                FomodPlugin plugin;
                                plugin.name = xmlAttribute(pluginElement, "name");
                                plugin.description = xmlText(firstChildElementNamed(pluginElement, "description"));
                                parseFomodFiles(firstChildElementNamed(pluginElement, "files"), plugin.files);

                                const TiXmlElement* flags = firstChildElementNamed(pluginElement, "conditionFlags");
                                if (flags)
                                {
                                    for (const TiXmlElement* flagElement = flags->FirstChildElement("flag"); flagElement;
                                         flagElement = flagElement->NextSiblingElement("flag"))
                                    {
                                        FomodFlag flag;
                                        flag.name = xmlAttribute(flagElement, "name");
                                        flag.value = xmlText(flagElement);
                                        if (!flag.name.empty())
                                            plugin.flags.push_back(flag);
                                    }
                                }

                                if (!plugin.name.empty())
                                    group.plugins.push_back(plugin);
                            }
                        }

                        if (!group.plugins.empty())
                            step.groups.push_back(group);
                    }
                }

                if (!step.groups.empty())
                    config.steps.push_back(step);
            }
        }

        const TiXmlElement* conditionalInstalls = firstChildElementNamed(root, "conditionalFileInstalls");
        if (conditionalInstalls)
        {
            for (const TiXmlElement* patternElement = conditionalInstalls->FirstChildElement("pattern"); patternElement;
                 patternElement = patternElement->NextSiblingElement("pattern"))
            {
                FomodConditionalPattern pattern;
                pattern.dependencies = parseFomodDependencyNode(firstChildElementNamed(patternElement, "dependencies"));
                parseFomodFiles(firstChildElementNamed(patternElement, "files"), pattern.files);
                if (!pattern.files.empty())
                    config.conditionalPatterns.push_back(pattern);
            }
        }

        return config;
    }

    bool evaluateFomodDependency(const FomodDependency& dependency, const FomodInstallState& state)
    {
        switch (dependency.type)
        {
            case FomodDependency::Type_None:
                return true;
            case FomodDependency::Type_And:
                for (std::size_t i = 0; i < dependency.children.size(); ++i)
                {
                    if (!evaluateFomodDependency(dependency.children[i], state))
                        return false;
                }
                return true;
            case FomodDependency::Type_Or:
                if (dependency.children.empty())
                    return true;
                for (std::size_t i = 0; i < dependency.children.size(); ++i)
                {
                    if (evaluateFomodDependency(dependency.children[i], state))
                        return true;
                }
                return false;
            case FomodDependency::Type_Flag:
            {
                std::map<std::string, std::string>::const_iterator it = state.flags.find(dependency.name);
                return it != state.flags.end() && it->second == dependency.value;
            }
            case FomodDependency::Type_File:
            {
                const std::string fileName = toLower(dependency.name);
                const bool available = state.availableFiles.count(fileName) > 0;
                const bool active = state.activeFiles.count(fileName) > 0;
                if (dependency.state == "active")
                    return active;
                if (dependency.state == "inactive")
                    return available && !active;
                if (dependency.state == "missing")
                    return !available;
                return available;
            }
            case FomodDependency::Type_Game:
                return true;
        }
        return true;
    }

    std::filesystem::path findFomodConfigPath(const std::filesystem::path& root)
    {
        std::error_code ec;
        for (std::filesystem::recursive_directory_iterator it(root, ec); !ec && it != std::filesystem::recursive_directory_iterator();
             it.increment(ec))
        {
            if (!it->is_regular_file(ec))
                continue;
            if (toLower(it->path().filename().string()) == "moduleconfig.xml")
                return it->path();
        }
        return std::filesystem::path();
    }

    std::filesystem::path installedModDataPath(const std::filesystem::path& root)
    {
        const std::filesystem::path fomodRoot = root / "_openmw_fomod";
        if (std::filesystem::exists(fomodRoot))
            return resolveExtractedDataPath(fomodRoot);
        return resolveExtractedDataPath(root);
    }

    bool copyFomodEntry(
        const std::filesystem::path& extractedRoot, const std::filesystem::path& installRoot, const FomodFileEntry& entry, std::string& error)
    {
        const std::filesystem::path sourcePath = extractedRoot / normalizeArchiveRelativePath(entry.source);
        if (!std::filesystem::exists(sourcePath))
        {
            error = "FOMOD source path missing: " + pathToString(sourcePath);
            return false;
        }

        std::filesystem::path destinationPath = installRoot / normalizeInstallDestination(entry.destination);
        std::error_code ec;
        if (std::filesystem::is_directory(sourcePath))
        {
            std::filesystem::create_directories(destinationPath, ec);
            for (std::filesystem::recursive_directory_iterator it(sourcePath, ec); !ec && it != std::filesystem::recursive_directory_iterator();
                 it.increment(ec))
            {
                const std::filesystem::path current = it->path();
                const std::filesystem::path relative = std::filesystem::relative(current, sourcePath, ec);
                const std::filesystem::path target = destinationPath / relative;
                if (it->is_directory(ec))
                    std::filesystem::create_directories(target, ec);
                else if (it->is_regular_file(ec))
                {
                    std::filesystem::create_directories(target.parent_path(), ec);
                    std::filesystem::copy_file(current, target, std::filesystem::copy_options::overwrite_existing, ec);
                }
                if (ec)
                {
                    error = "Failed copying FOMOD folder contents.";
                    return false;
                }
            }
            return true;
        }

        const bool destinationLooksLikeFile = !destinationPath.empty() && !destinationPath.has_filename()
            ? false
            : (!destinationPath.empty() && !sourcePath.filename().empty()
                && toLower(destinationPath.filename().string()) != toLower(sourcePath.filename().string())
                && destinationPath.extension() != "");
        if (destinationPath.empty() || (!destinationLooksLikeFile && destinationPath.extension().empty()))
            destinationPath /= sourcePath.filename();

        std::filesystem::create_directories(destinationPath.parent_path(), ec);
        std::filesystem::copy_file(sourcePath, destinationPath, std::filesystem::copy_options::overwrite_existing, ec);
        if (ec)
        {
            error = "Failed copying FOMOD file.";
            return false;
        }
        return true;
    }

    bool promptForSingleChoice(const std::string& title, const FomodGroup& group, bool allowNone, int& selectedIndex)
    {
        NSAlert* alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:toNSString(title)];
        [alert setInformativeText:toNSString(group.name)];
        [alert addButtonWithTitle:@"Install"];
        [alert addButtonWithTitle:@"Cancel"];

        NSPopUpButton* popup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 340, 26) pullsDown:NO] autorelease];
        if (allowNone)
            [popup addItemWithTitle:@"Do not install this group"];
        for (std::size_t i = 0; i < group.plugins.size(); ++i)
            [popup addItemWithTitle:toNSString(group.plugins[i].name)];
        [alert setAccessoryView:popup];

        if ([alert runModal] != NSAlertFirstButtonReturn)
            return false;

        NSInteger index = [popup indexOfSelectedItem];
        selectedIndex = allowNone ? static_cast<int>(index) - 1 : static_cast<int>(index);
        return true;
    }

    bool promptForMultiChoice(const std::string& title, const FomodGroup& group, bool requireOne, std::vector<int>& selectedIndices)
    {
        NSAlert* alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:toNSString(title)];
        [alert setInformativeText:toNSString(group.name)];
        [alert addButtonWithTitle:@"Install"];
        [alert addButtonWithTitle:@"Cancel"];

        const CGFloat rowHeight = 24.0f;
        const CGFloat height = std::max<CGFloat>(60.0f, 8.0f + rowHeight * static_cast<CGFloat>(group.plugins.size()));
        NSView* accessory = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, height)] autorelease];
        NSMutableArray* checkboxes = [NSMutableArray array];
        CGFloat y = height - rowHeight;
        for (std::size_t i = 0; i < group.plugins.size(); ++i)
        {
            NSButton* button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, y, 350, 22)] autorelease];
            [button setButtonType:NSSwitchButton];
            [button setTitle:toNSString(group.plugins[i].name)];
            [accessory addSubview:button];
            [checkboxes addObject:button];
            y -= rowHeight;
        }
        [alert setAccessoryView:accessory];

        if ([alert runModal] != NSAlertFirstButtonReturn)
            return false;

        for (NSUInteger i = 0; i < [checkboxes count]; ++i)
        {
            if ([(NSButton*)[checkboxes objectAtIndex:i] state] == NSOnState)
                selectedIndices.push_back(static_cast<int>(i));
        }

        if (requireOne && selectedIndices.empty())
        {
            NSRunAlertPanel(@"Selection Required", @"Choose at least one option to continue.", @"OK", nil, nil);
            return promptForMultiChoice(title, group, requireOne, selectedIndices);
        }

        return true;
    }

    bool hasExtension(const std::filesystem::path& path, const char* extension)
    {
        std::string ext = path.extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return ext == extension;
    }

    void sortUnique(std::vector<std::string>& values)
    {
        std::sort(values.begin(), values.end());
        values.erase(std::unique(values.begin(), values.end()), values.end());
    }

    std::string toLower(std::string value)
    {
        std::transform(
            value.begin(), value.end(), value.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return value;
    }

    int contentPriority(const std::string& filename)
    {
        const std::string lower = toLower(filename);
        if (lower == "morrowind.esm")
            return 0;
        if (lower == "tribunal.esm")
            return 1;
        if (lower == "bloodmoon.esm")
            return 2;
        if (lower.size() >= 4 && lower.substr(lower.size() - 4) == ".esm")
            return 3;
        return 4;
    }

    void sortContentFiles(std::vector<std::string>& values)
    {
        std::sort(values.begin(), values.end(), [](const std::string& lhs, const std::string& rhs) {
            const int lhsPriority = contentPriority(lhs);
            const int rhsPriority = contentPriority(rhs);
            if (lhsPriority != rhsPriority)
                return lhsPriority < rhsPriority;
            return toLower(lhs) < toLower(rhs);
        });
        values.erase(std::unique(values.begin(), values.end()), values.end());
    }

    class LauncherService
    {
    public:
        LauncherService()
            : mCfgMgr(true)
        {
            initializeConfiguration(mCfgMgr);
            mUserConfigPath = mCfgMgr.getUserConfigPath();
            mOpenMWCfgPath = mUserConfigPath / Files::openmwCfgFile;
            mSettingsPath = mUserConfigPath / "settings.cfg";
            mModsPath = mUserConfigPath / "mods";
        }

        LauncherModel load()
        {
            LauncherModel model;
            mConfig.load(mOpenMWCfgPath);
            model.dataDirs = mConfig.dataDirs;
            model.archives = mConfig.archives;
            model.contentFiles = mConfig.contentFiles;
            model.importerIni = detectIni(model.dataDirs);

            Settings::Manager::clear();
            Settings::Manager::load(mCfgMgr);
            model.resolutionX = Settings::Manager::getOrDefault<int>("resolution x", "Video", 800);
            model.resolutionY = Settings::Manager::getOrDefault<int>("resolution y", "Video", 600);
            model.screen = Settings::Manager::getOrDefault<int>("screen", "Video", 0);
            model.windowMode = Settings::Manager::getOrDefault<Settings::WindowMode>(
                "window mode", "Video", Settings::WindowMode::Windowed);
            model.windowBorder = Settings::Manager::getOrDefault<bool>("window border", "Video", true);
            model.vsyncMode
                = Settings::Manager::getOrDefault<SDLUtil::VSyncMode>("vsync mode", "Video", SDLUtil::Enabled);
            model.frameRateLimit = static_cast<int>(
                Settings::Manager::getOrDefault<float>("framerate limit", "Video", 60.f));
            model.antialiasing = Settings::Manager::getOrDefault<int>("antialiasing", "Video", 0);
            model.anisotropy = static_cast<int>(Settings::Manager::getOrDefault<float>("anisotropy", "General", 4.f));
            model.lightingMethod = static_cast<int>(Settings::Manager::getOrDefault<SceneUtil::LightingMethod>(
                "lighting method", "Shaders", SceneUtil::LightingMethod::PerObjectUniform));
            model.viewingDistance = Settings::Manager::getOrDefault<float>("viewing distance", "Camera", 8192.f * 4.f);
            model.objectPagingMinSize
                = Settings::Manager::getOrDefault<float>("object paging min size", "Terrain", 0.09f);
            model.textureMagFilter
                = Settings::Manager::getOrDefault<std::string>("texture mag filter", "General", "linear");
            model.textureMinFilter
                = Settings::Manager::getOrDefault<std::string>("texture min filter", "General", "linear");
            model.textureMipmap = Settings::Manager::getOrDefault<std::string>("texture mipmap", "General", "nearest");
            model.softParticles = Settings::Manager::getOrDefault<bool>("soft particles", "Shaders", false);
            model.radialFog = Settings::Manager::getOrDefault<bool>("radial fog", "Fog", false);
            model.exponentialFog = Settings::Manager::getOrDefault<bool>("exponential fog", "Fog", false);
            model.skyBlending = Settings::Manager::getOrDefault<bool>("sky blending", "Fog", false);
            model.skyBlendingStart = Settings::Manager::getOrDefault<float>("sky blending start", "Fog", 0.1f);
            model.distantTerrain = Settings::Manager::getOrDefault<bool>("distant terrain", "Terrain", false);
            model.objectPaging = Settings::Manager::getOrDefault<bool>("object paging", "Terrain", true);
            model.objectPagingActiveGrid
                = Settings::Manager::getOrDefault<bool>("object paging active grid", "Terrain", true);
            model.groundcover = Settings::Manager::getOrDefault<bool>("enabled", "Groundcover", false);
            model.weatherParticleOcclusion
                = Settings::Manager::getOrDefault<bool>("weather particle occlusion", "Shaders", false);
            model.postProcessing = Settings::Manager::getOrDefault<bool>("enabled", "Post Processing", false);
            model.transparentPostpass
                = Settings::Manager::getOrDefault<bool>("transparent postpass", "Post Processing", false);
            model.postProcessExposureSpeed
                = Settings::Manager::getOrDefault<float>("auto exposure speed", "Post Processing", 1.f);
            model.shadows = Settings::Manager::getOrDefault<bool>("enable shadows", "Shadows", false);
            model.actorShadows = Settings::Manager::getOrDefault<bool>("actor shadows", "Shadows", false);
            model.playerShadows = Settings::Manager::getOrDefault<bool>("player shadows", "Shadows", false);
            model.terrainShadows = Settings::Manager::getOrDefault<bool>("terrain shadows", "Shadows", false);
            model.objectShadows = Settings::Manager::getOrDefault<bool>("object shadows", "Shadows", false);
            model.indoorShadows = Settings::Manager::getOrDefault<bool>("enable indoor shadows", "Shadows", false);
            model.shadowDistance
                = Settings::Manager::getOrDefault<float>("maximum shadow map distance", "Shadows", 0.f);
            model.shadowFadeStart = Settings::Manager::getOrDefault<float>("shadow fade start", "Shadows", 0.f);
            model.shadowMapResolution
                = Settings::Manager::getOrDefault<int>("shadow map resolution", "Shadows", 1024);
            model.shadowComputeSceneBounds
                = Settings::Manager::getOrDefault<std::string>("compute scene bounds", "Shadows", "bounds");
            model.waterShader = Settings::Manager::getOrDefault<bool>("shader", "Water", false);
            model.waterRefraction = Settings::Manager::getOrDefault<bool>("refraction", "Water", false);
            model.waterSunlightScattering
                = Settings::Manager::getOrDefault<bool>("sunlight scattering", "Water", false);
            model.waterWobblyShores = Settings::Manager::getOrDefault<bool>("wobbly shores", "Water", false);
            model.waterReflectionDetail = Settings::Manager::getOrDefault<int>("reflection detail", "Water", 0);

            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            model.skipMenu = [defaults boolForKey:@"LauncherSkipMenu"];
            model.threadingMode = fromNSString([defaults stringForKey:@"LauncherThreadingMode"]);
            return model;
        }

        bool save(const LauncherModel& model)
        {
            std::error_code ec;
            std::filesystem::create_directories(mUserConfigPath, ec);

            mConfig.dataDirs = model.dataDirs;
            mConfig.archives = model.archives;
            mConfig.contentFiles = model.contentFiles;

            if (!mConfig.save(mOpenMWCfgPath))
                return false;

            Settings::Manager::clear();
            Settings::Manager::load(mCfgMgr);
            Settings::Manager::set("resolution x", "Video", model.resolutionX);
            Settings::Manager::set("resolution y", "Video", model.resolutionY);
            Settings::Manager::set("screen", "Video", model.screen);
            Settings::Manager::set("window mode", "Video", model.windowMode);
            Settings::Manager::set("window border", "Video", model.windowBorder);
            Settings::Manager::set("vsync mode", "Video", model.vsyncMode);
            Settings::Manager::set("framerate limit", "Video", static_cast<float>(model.frameRateLimit));
            Settings::Manager::set("antialiasing", "Video", model.antialiasing);
            Settings::Manager::set("anisotropy", "General", static_cast<float>(model.anisotropy));
            Settings::Manager::set(
                "lighting method", "Shaders", static_cast<SceneUtil::LightingMethod>(model.lightingMethod));
            Settings::Manager::set("viewing distance", "Camera", model.viewingDistance);
            Settings::Manager::set("object paging min size", "Terrain", model.objectPagingMinSize);
            Settings::Manager::set("texture mag filter", "General", model.textureMagFilter);
            Settings::Manager::set("texture min filter", "General", model.textureMinFilter);
            Settings::Manager::set("texture mipmap", "General", model.textureMipmap);
            Settings::Manager::set("soft particles", "Shaders", model.softParticles);
            Settings::Manager::set("radial fog", "Fog", model.radialFog);
            Settings::Manager::set("exponential fog", "Fog", model.exponentialFog);
            Settings::Manager::set("sky blending", "Fog", model.skyBlending);
            Settings::Manager::set("sky blending start", "Fog", model.skyBlendingStart);
            Settings::Manager::set("distant terrain", "Terrain", model.distantTerrain);
            Settings::Manager::set("object paging", "Terrain", model.objectPaging);
            Settings::Manager::set("object paging active grid", "Terrain", model.objectPagingActiveGrid);
            Settings::Manager::set("enabled", "Groundcover", model.groundcover);
            Settings::Manager::set("weather particle occlusion", "Shaders", model.weatherParticleOcclusion);
            Settings::Manager::set("enabled", "Post Processing", model.postProcessing);
            Settings::Manager::set("transparent postpass", "Post Processing", model.transparentPostpass);
            Settings::Manager::set("auto exposure speed", "Post Processing", model.postProcessExposureSpeed);
            Settings::Manager::set("enable shadows", "Shadows", model.shadows);
            Settings::Manager::set("actor shadows", "Shadows", model.actorShadows);
            Settings::Manager::set("player shadows", "Shadows", model.playerShadows);
            Settings::Manager::set("terrain shadows", "Shadows", model.terrainShadows);
            Settings::Manager::set("object shadows", "Shadows", model.objectShadows);
            Settings::Manager::set("enable indoor shadows", "Shadows", model.indoorShadows);
            Settings::Manager::set("maximum shadow map distance", "Shadows", model.shadowDistance);
            Settings::Manager::set("shadow fade start", "Shadows", model.shadowFadeStart);
            Settings::Manager::set("shadow map resolution", "Shadows", model.shadowMapResolution);
            Settings::Manager::set("compute scene bounds", "Shadows", model.shadowComputeSceneBounds);
            Settings::Manager::set("shader", "Water", model.waterShader);
            Settings::Manager::set("refraction", "Water", model.waterRefraction);
            Settings::Manager::set("sunlight scattering", "Water", model.waterSunlightScattering);
            Settings::Manager::set("wobbly shores", "Water", model.waterWobblyShores);
            Settings::Manager::set("reflection detail", "Water", model.waterReflectionDetail);

            Settings::Manager::saveUser(mSettingsPath);

            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            [defaults setBool:model.skipMenu forKey:@"LauncherSkipMenu"];
            [defaults setObject:toNSString(model.threadingMode) forKey:@"LauncherThreadingMode"];
            [defaults synchronize];
            return true;
        }

        bool launchOpenMW(const LauncherModel& model, std::string& error)
        {
            if (!save(model))
            {
                error = "Failed to save launcher settings.";
                return false;
            }

            NSString* executablePath = [[NSBundle mainBundle] executablePath];
            NSString* binaryDir = [executablePath stringByDeletingLastPathComponent];
            NSString* openmwPath = [binaryDir stringByAppendingPathComponent:@"openmw"];

            NSFileManager* fm = [NSFileManager defaultManager];
            std::vector<std::string> args;
            if (model.skipMenu)
                args.push_back("--skip-menu");
            if ([fm isExecutableFileAtPath:openmwPath])
                return launchProcess(fromNSString(openmwPath), args, model.threadingMode, error);

            return launchProcess("openmw", args, model.threadingMode, error);
        }

        bool runTool(const std::string& toolName, const std::vector<std::string>& args, std::string& error)
        {
            NSString* executablePath = [[NSBundle mainBundle] executablePath];
            NSString* binaryDir = [executablePath stringByDeletingLastPathComponent];
            NSString* toolPath = [binaryDir stringByAppendingPathComponent:toNSString(toolName)];

            NSFileManager* fm = [NSFileManager defaultManager];
            if ([fm isExecutableFileAtPath:toolPath])
                return launchProcess(fromNSString(toolPath), args, std::string(), error);

            return launchProcess(toolName, args, std::string(), error);
        }

        const std::filesystem::path& getUserConfigPath() const { return mUserConfigPath; }
        const std::filesystem::path& getModsPath() const { return mModsPath; }

        void scanDataDirectories(const std::vector<std::string>& dataDirs, std::vector<std::string>& archives,
            std::vector<std::string>& contentFiles) const
        {
            archives.clear();
            contentFiles.clear();

            for (std::vector<std::string>::const_iterator it = dataDirs.begin(); it != dataDirs.end(); ++it)
            {
                std::error_code ec;
                const std::filesystem::path dir(*it);
                if (!std::filesystem::is_directory(dir, ec))
                    continue;

                for (std::filesystem::directory_iterator entry(dir, ec); !ec && entry != std::filesystem::directory_iterator();
                     entry.increment(ec))
                {
                    const std::filesystem::path path = entry->path();
                    if (!entry->is_regular_file(ec))
                        continue;

                    const std::string filename = path.filename().string();
                    if (hasExtension(path, ".bsa"))
                        archives.push_back(filename);
                    else if (hasExtension(path, ".esm") || hasExtension(path, ".esp") || hasExtension(path, ".omwgame")
                        || hasExtension(path, ".omwaddon"))
                        contentFiles.push_back(filename);
                }
            }

            sortUnique(archives);
            sortContentFiles(contentFiles);
        }

        bool extractArchive(const std::string& archivePath, std::string& extractedRoot, std::string& error)
        {
            const std::filesystem::path tool = findArchiveTool();
            if (tool.empty())
            {
                error = "Archive support requires /opt/local/bin/7za or /opt/local/bin/7z.";
                return false;
            }

            const std::filesystem::path source(archivePath);
            if (!std::filesystem::exists(source))
            {
                error = "Archive file not found.";
                return false;
            }

            std::error_code ec;
            std::filesystem::create_directories(mModsPath, ec);
            std::filesystem::path targetBase = uniquePath(
                mModsPath / sanitizePathComponent(source.stem().string()));
            std::filesystem::create_directories(targetBase, ec);
            if (ec)
            {
                error = "Failed to create mod install directory.";
                return false;
            }

            std::vector<std::string> args;
            args.push_back("x");
            args.push_back(pathToString(source));
            args.push_back("-y");
            args.push_back("-o" + pathToString(targetBase));

            if (!runToolAndWait(pathToString(tool), args, error))
                return false;

            extractedRoot = pathToString(targetBase);
            return true;
        }

    private:
        static std::filesystem::path findArchiveTool()
        {
            static const char* const candidates[] = {
                "/opt/local/bin/7za",
                "/opt/local/bin/7z",
                "/usr/local/bin/7za",
                "/usr/local/bin/7z"
            };

            for (std::size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i)
            {
                std::filesystem::path path(candidates[i]);
                if (std::filesystem::exists(path))
                    return path;
            }

            return std::filesystem::path();
        }

        static bool runToolAndWait(
            const std::string& executable, const std::vector<std::string>& args, std::string& error)
        {
            std::vector<std::string> argvStorage;
            argvStorage.reserve(args.size() + 1);
            argvStorage.push_back(executable);
            for (std::vector<std::string>::const_iterator it = args.begin(); it != args.end(); ++it)
                argvStorage.push_back(*it);

            std::vector<char*> argv;
            argv.reserve(argvStorage.size() + 1);
            for (std::vector<std::string>::iterator it = argvStorage.begin(); it != argvStorage.end(); ++it)
                argv.push_back(const_cast<char*>(it->c_str()));
            argv.push_back(0);

            const pid_t pid = fork();
            if (pid < 0)
            {
                error = "Failed to start archive extraction.";
                return false;
            }

            if (pid == 0)
            {
                execv(executable.c_str(), &argv[0]);
                _exit(127);
            }

            int status = 0;
            if (waitpid(pid, &status, 0) < 0)
            {
                error = "Failed waiting for archive extraction.";
                return false;
            }

            if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
            {
                error = "Archive extraction failed.";
                return false;
            }

            return true;
        }

        static bool launchProcess(const std::string& executable, const std::vector<std::string>& args,
            const std::string& threadingMode, std::string& error)
        {
            std::vector<std::string> argvStorage;
            argvStorage.reserve(args.size() + 1);
            argvStorage.push_back(executable);
            for (std::vector<std::string>::const_iterator it = args.begin(); it != args.end(); ++it)
                argvStorage.push_back(*it);

            std::vector<char*> argv;
            argv.reserve(argvStorage.size() + 1);
            for (std::vector<std::string>::iterator it = argvStorage.begin(); it != argvStorage.end(); ++it)
                argv.push_back(const_cast<char*>(it->c_str()));
            argv.push_back(0);

            const pid_t pid = fork();
            if (pid < 0)
            {
                error = "Failed to fork launcher process.";
                return false;
            }

            if (pid == 0)
            {
                if (threadingMode.empty())
                    unsetenv("OSG_THREADING");
                else
                    setenv("OSG_THREADING", threadingMode.c_str(), 1);

                if (executable.find('/') != std::string::npos)
                    execv(executable.c_str(), &argv[0]);
                else
                    execvp(executable.c_str(), &argv[0]);
                _exit(127);
            }

            return true;
        }

        static std::string detectIni(const std::vector<std::string>& dataDirs)
        {
            for (std::vector<std::string>::const_iterator it = dataDirs.begin(); it != dataDirs.end(); ++it)
            {
                std::filesystem::path dataPath(*it);
                std::filesystem::path ini = dataPath / "Morrowind.ini";
                if (std::filesystem::exists(ini))
                    return pathToString(ini);
                ini = dataPath.parent_path() / "Morrowind.ini";
                if (std::filesystem::exists(ini))
                    return pathToString(ini);
            }
            return std::string();
        }

        Files::ConfigurationManager mCfgMgr;
        OpenMWUserConfig mConfig;
        std::filesystem::path mUserConfigPath;
        std::filesystem::path mOpenMWCfgPath;
        std::filesystem::path mSettingsPath;
        std::filesystem::path mModsPath;
    };
}

@interface LauncherDropView : NSView
{
    id mTarget;
    SEL mAction;
    NSString* mPrompt;
}
- (void)setDropTarget:(id)target action:(SEL)action;
- (void)setPrompt:(NSString*)prompt;
@end

@interface OpenMWCocoaLauncher : NSObject
{
    NSWindow* mWindow;
    NSSegmentedControl* mPageSelector;
    NSView* mPageContainer;
    NSView* mDataPage;
    NSView* mModsPage;
    NSView* mGraphicsPage;
    NSTabView* mModsTabView;
    NSTabView* mVideoTabView;
    LauncherDropView* mDataDropView;
    LauncherDropView* mModsDropView;
    NSScrollView* mDataDirsTableScrollView;
    NSTableView* mDataDirsTableView;
    NSTextField* mModsPathField;
    NSScrollView* mModsTableScrollView;
    NSTableView* mModsTableView;
    NSScrollView* mContentTableScrollView;
    NSTableView* mContentTableView;
    NSPopUpButton* mResolutionPopup;
    NSPopUpButton* mScreenPopup;
    NSPopUpButton* mWindowModePopup;
    NSPopUpButton* mVsyncPopup;
    NSPopUpButton* mThreadingPopup;
    NSButton* mWindowBorderCheck;
    NSPopUpButton* mTextureMagPopup;
    NSPopUpButton* mTextureMinPopup;
    NSPopUpButton* mTextureMipmapPopup;
    NSTextField* mFrameRateField;
    NSPopUpButton* mAntialiasingPopup;
    NSPopUpButton* mAnisotropyPopup;
    NSSlider* mViewingDistanceSlider;
    NSTextField* mViewingDistanceValueLabel;
    NSSlider* mObjectPagingMinSizeSlider;
    NSTextField* mObjectPagingMinSizeValueLabel;
    NSTextField* mWaterReflectionDetailField;
    NSTextField* mPostProcessExposureField;
    NSTextField* mSkyBlendingStartField;
    NSTextField* mShadowDistanceField;
    NSTextField* mShadowFadeField;
    NSTextField* mShadowResolutionField;
    NSPopUpButton* mLightingMethodPopup;
    NSPopUpButton* mShadowBoundsPopup;
    NSButton* mSkipMenuCheck;
    NSButton* mSoftParticlesCheck;
    NSButton* mSkyBlendingCheck;
    NSButton* mDistantTerrainCheck;
    NSButton* mObjectPagingCheck;
    NSButton* mObjectPagingActiveGridCheck;
    NSButton* mGroundcoverCheck;
    NSButton* mWeatherOcclusionCheck;
    NSButton* mPostProcessingCheck;
    NSButton* mTransparentPostpassCheck;
    NSButton* mRadialFogCheck;
    NSButton* mExponentialFogCheck;
    NSButton* mShadowsCheck;
    NSButton* mActorShadowsCheck;
    NSButton* mPlayerShadowsCheck;
    NSButton* mTerrainShadowsCheck;
    NSButton* mObjectShadowsCheck;
    NSButton* mIndoorShadowsCheck;
    NSButton* mWaterShaderCheck;
    NSButton* mWaterRefractionCheck;
    NSButton* mWaterScatteringCheck;
    NSButton* mWaterWobblyCheck;
    NSTextField* mStatusField;
    LauncherService* mService;
    LauncherModel mModel;
    std::vector<InstalledModInfo> mInstalledMods;
    std::vector<std::string> mDetectedArchives;
    std::vector<std::string> mDetectedContentFiles;
}
- (void)buildWindow;
- (void)buildDataPage;
- (void)buildModsPage;
- (void)buildGraphicsPage;
- (void)showPageAtIndex:(NSInteger)index;
- (NSButton*)checkboxWithTitle:(NSString*)title frame:(NSRect)frame;
- (NSTextField*)sectionLabel:(NSString*)text frame:(NSRect)frame;
- (void)populateResolutionPopup;
- (void)screenChanged:(id)sender;
- (void)refreshGraphicsValueLabels;
- (void)refreshGraphicsControlAvailability:(id)sender;
- (void)loadModelIntoControls;
- (void)pullControlsIntoModel;
- (void)setStatus:(const std::string&)text;
- (void)reload:(id)sender;
- (void)save:(id)sender;
- (void)launch:(id)sender;
- (void)refreshScannedData;
- (void)reloadDataDirsTable;
- (void)reloadModsTable;
- (void)syncSelectionsToModel;
- (void)reloadContentTable;
- (void)addDataDirectoryPaths:(NSArray*)paths;
- (void)removeAllDataDirs:(id)sender;
- (void)deleteSelectedDataDir:(id)sender;
- (void)moveDataDirUp:(id)sender;
- (void)moveDataDirDown:(id)sender;
- (void)handleDroppedPaths:(NSArray*)paths;
- (void)handleModDroppedPaths:(NSArray*)paths;
@end

@implementation LauncherDropView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
        mPrompt = [@"Drop Data Files folder here" retain];
    }
    return self;
}

- (void)dealloc
{
    [mPrompt release];
    [super dealloc];
}

- (void)setDropTarget:(id)target action:(SEL)action
{
    mTarget = target;
    mAction = action;
}

- (void)setPrompt:(NSString*)prompt
{
    if (mPrompt == prompt)
        return;
    [mPrompt release];
    mPrompt = [prompt copy];
    [self setNeedsDisplay:YES];
}

- (unsigned int)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSFilenamesPboardType])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
    (void)sender;
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];
    NSArray* files = [pboard propertyListForType:NSFilenamesPboardType];
    if (mTarget && mAction && files)
    {
        [mTarget performSelector:mAction withObject:files];
        return YES;
    }
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] set];
    NSRectFill([self bounds]);

    [[NSColor grayColor] set];
    NSFrameRectWithWidth([self bounds], 2.0);

    NSDictionary* attrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:18], NSFontAttributeName,
        [NSColor darkGrayColor], NSForegroundColorAttributeName,
        nil];
    NSSize size = [mPrompt sizeWithAttributes:attrs];
    NSRect bounds = [self bounds];
    NSPoint point = NSMakePoint((bounds.size.width - size.width) / 2.0, (bounds.size.height - size.height) / 2.0);
    [mPrompt drawAtPoint:point withAttributes:attrs];
}

@end

@implementation OpenMWCocoaLauncher

- (id)init
{
    self = [super init];
    if (self)
    {
        Log(Debug::Info) << "Launcher-Cocoa: init";
        mService = new LauncherService();
    }
    return self;
}

- (void)dealloc
{
    Log(Debug::Info) << "Launcher-Cocoa: dealloc";
    [mWindow release];
    delete mService;
    [super dealloc];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
    (void)sender;
    Log(Debug::Info) << "Launcher-Cocoa: applicationShouldTerminateAfterLastWindowClosed -> YES";
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
    (void)notification;
    Log(Debug::Info) << "Launcher-Cocoa: applicationDidFinishLaunching";
    mModel = mService->load();
    Log(Debug::Info) << "Launcher-Cocoa: model loaded";
    [self buildWindow];
    Log(Debug::Info) << "Launcher-Cocoa: window built";
    [self loadModelIntoControls];
    Log(Debug::Info) << "Launcher-Cocoa: controls populated";
    [mWindow makeKeyAndOrderFront:nil];
    Log(Debug::Info) << "Launcher-Cocoa: window ordered front";
    [NSApp activateIgnoringOtherApps:YES];
    Log(Debug::Info) << "Launcher-Cocoa: app activated";
}

- (void)windowWillClose:(NSNotification*)notification
{
    (void)notification;
    Log(Debug::Info) << "Launcher-Cocoa: windowWillClose";
    [self save:nil];
}

- (NSTextField*)label:(NSString*)text frame:(NSRect)frame
{
    NSTextField* field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setStringValue:text];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    return field;
}

- (void)buildWindow
{
    Log(Debug::Info) << "Launcher-Cocoa: buildWindow begin";
    if (mWindow)
    {
        [mWindow release];
        mWindow = nil;
    }

    const NSRect windowRect = NSMakeRect(200, 200, 780, 560);
    const NSRect pageRect = NSMakeRect(20, 70, 740, 430);

    mWindow = [[NSWindow alloc] initWithContentRect:windowRect
                                          styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [mWindow setTitle:@"OpenMW Cocoa Launcher"];
    [mWindow setDelegate:self];
    [mWindow setMinSize:NSMakeSize(780, 560)];

    NSView* contentView = [mWindow contentView];
    mPageSelector = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(20, 515, 520, 28)] autorelease];
    [mPageSelector setSegmentCount:3];
    [mPageSelector setLabel:@"Game Folders" forSegment:0];
    [mPageSelector setLabel:@"Mods" forSegment:1];
    [mPageSelector setLabel:@"Video" forSegment:2];
    [mPageSelector setTarget:self];
    [mPageSelector setAction:@selector(changePage:)];
    [mPageSelector setSelectedSegment:0];
    [contentView addSubview:mPageSelector];

    mPageContainer = [[[NSView alloc] initWithFrame:pageRect] autorelease];
    [contentView addSubview:mPageContainer];

    [self buildDataPage];
    [self buildModsPage];
    [self buildGraphicsPage];
    [self showPageAtIndex:0];

    NSButton* reloadButton = [[[NSButton alloc] initWithFrame:NSMakeRect(20, 24, 100, 32)] autorelease];
    [reloadButton setTitle:@"Reload"];
    [reloadButton setBezelStyle:NSRoundedBezelStyle];
    [reloadButton setTarget:self];
    [reloadButton setAction:@selector(reload:)];
    [contentView addSubview:reloadButton];

    NSButton* saveButton = [[[NSButton alloc] initWithFrame:NSMakeRect(130, 24, 100, 32)] autorelease];
    [saveButton setTitle:@"Save"];
    [saveButton setBezelStyle:NSRoundedBezelStyle];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(save:)];
    [contentView addSubview:saveButton];

    NSButton* launchButton = [[[NSButton alloc] initWithFrame:NSMakeRect(600, 24, 160, 32)] autorelease];
    [launchButton setTitle:@"Launch OpenMW"];
    [launchButton setBezelStyle:NSRoundedBezelStyle];
    [launchButton setTarget:self];
    [launchButton setAction:@selector(launch:)];
    [contentView addSubview:launchButton];

    mStatusField = [[[NSTextField alloc] initWithFrame:NSMakeRect(250, 28, 330, 24)] autorelease];
    [mStatusField setBezeled:NO];
    [mStatusField setDrawsBackground:NO];
    [mStatusField setEditable:NO];
    [mStatusField setSelectable:NO];
    [mStatusField setStringValue:@"Ready."];
    [contentView addSubview:mStatusField];
    Log(Debug::Info) << "Launcher-Cocoa: buildWindow end";
}

- (void)buildDataPage
{
    mDataPage = [[[NSView alloc] initWithFrame:[mPageContainer bounds]] autorelease];
    [mDataPage addSubview:[self label:@"Game Folders" frame:NSMakeRect(0, 406, 220, 20)]];
    mDataDropView = [[[LauncherDropView alloc] initWithFrame:NSMakeRect(0, 250, 720, 146)] autorelease];
    [mDataDropView setDropTarget:self action:@selector(handleDroppedPaths:)];
    [mDataPage addSubview:mDataDropView];

    NSButton* clearButton = [[[NSButton alloc] initWithFrame:NSMakeRect(580, 402, 140, 28)] autorelease];
    [clearButton setTitle:@"Clear Directories"];
    [clearButton setBezelStyle:NSRoundedBezelStyle];
    [clearButton setTarget:self];
    [clearButton setAction:@selector(removeAllDataDirs:)];
    [mDataPage addSubview:clearButton];

    [mDataPage addSubview:[self label:@"Active folders" frame:NSMakeRect(0, 220, 220, 20)]];
    mDataDirsTableScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 720, 214)] autorelease];
    [mDataDirsTableScrollView setHasVerticalScroller:YES];
    [mDataDirsTableScrollView setHasHorizontalScroller:YES];
    [mDataDirsTableScrollView setBorderType:NSBezelBorder];

    mDataDirsTableView = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 720, 214)] autorelease];
    NSTableColumn* dataDirColumn = [[[NSTableColumn alloc] initWithIdentifier:@"dataDir"] autorelease];
    [dataDirColumn setWidth:680];
    [[dataDirColumn headerCell] setStringValue:@"Active Data Folder"];
    [mDataDirsTableView addTableColumn:dataDirColumn];
    [mDataDirsTableView setUsesAlternatingRowBackgroundColors:YES];
    [mDataDirsTableView setAllowsColumnReordering:NO];
    [mDataDirsTableView setAllowsMultipleSelection:NO];
    [mDataDirsTableView setDataSource:(id)self];
    [mDataDirsTableView setDelegate:(id)self];
    [mDataDirsTableView registerForDraggedTypes:[NSArray arrayWithObject:@"OpenMWDataDirRow"]];
    [mDataDirsTableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    NSMenu* dataDirsMenu = [[[NSMenu alloc] initWithTitle:@"Data Folders"] autorelease];
    NSMenuItem* deleteFolderItem
        = [[[NSMenuItem alloc] initWithTitle:@"Delete Folder" action:@selector(deleteSelectedDataDir:) keyEquivalent:@""] autorelease];
    [deleteFolderItem setTarget:self];
    [dataDirsMenu addItem:deleteFolderItem];
    [mDataDirsTableView setMenu:dataDirsMenu];
    [mDataDirsTableScrollView setDocumentView:mDataDirsTableView];
    [mDataPage addSubview:mDataDirsTableScrollView];
    [mPageContainer addSubview:mDataPage];
}

- (void)buildModsPage
{
    mModsPage = [[[NSView alloc] initWithFrame:[mPageContainer bounds]] autorelease];
    [mModsPage addSubview:[self label:@"Mods" frame:NSMakeRect(0, 406, 220, 20)]];
    mModsDropView = [[[LauncherDropView alloc] initWithFrame:NSMakeRect(0, 306, 720, 90)] autorelease];
    [mModsDropView setDropTarget:self action:@selector(handleModDroppedPaths:)];
    [mModsDropView setPrompt:@"Drop mod folder here"];
    [mModsPage addSubview:mModsDropView];

    [mModsPage addSubview:[self label:@"Installed mod root" frame:NSMakeRect(0, 274, 220, 20)]];
    mModsPathField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 244, 720, 24)] autorelease];
    [mModsPathField setBezeled:YES];
    [mModsPathField setEditable:NO];
    [mModsPathField setSelectable:YES];
    [mModsPage addSubview:mModsPathField];

    mModsTabView = [[[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 720, 236)] autorelease];

    NSTabViewItem* installedTab = [[[NSTabViewItem alloc] initWithIdentifier:@"installed"] autorelease];
    [installedTab setLabel:@"Installed Mods"];
    NSView* installedView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 206)] autorelease];
    [installedView addSubview:[self label:@"Installed vs active folder mods" frame:NSMakeRect(0, 184, 280, 20)]];
    mModsTableScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 720, 178)] autorelease];
    [mModsTableScrollView setHasVerticalScroller:YES];
    [mModsTableScrollView setHasHorizontalScroller:YES];
    [mModsTableScrollView setBorderType:NSBezelBorder];

    mModsTableView = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 720, 178)] autorelease];
    NSTableColumn* modEnabledColumn = [[[NSTableColumn alloc] initWithIdentifier:@"modEnabled"] autorelease];
    [modEnabledColumn setWidth:44];
    [[modEnabledColumn headerCell] setStringValue:@"Active"];
    NSButtonCell* modCheckboxCell = [[[NSButtonCell alloc] init] autorelease];
    [modCheckboxCell setButtonType:NSSwitchButton];
    [modCheckboxCell setTitle:@""];
    [modCheckboxCell setImagePosition:NSImageOnly];
    [modEnabledColumn setDataCell:modCheckboxCell];
    [mModsTableView addTableColumn:modEnabledColumn];

    NSTableColumn* modNameColumn = [[[NSTableColumn alloc] initWithIdentifier:@"modName"] autorelease];
    [modNameColumn setWidth:220];
    [[modNameColumn headerCell] setStringValue:@"Installed Mod"];
    [mModsTableView addTableColumn:modNameColumn];

    NSTableColumn* modPathColumn = [[[NSTableColumn alloc] initWithIdentifier:@"modPath"] autorelease];
    [modPathColumn setWidth:430];
    [[modPathColumn headerCell] setStringValue:@"Active Data Folder"];
    [mModsTableView addTableColumn:modPathColumn];

    [mModsTableView setUsesAlternatingRowBackgroundColors:YES];
    [mModsTableView setAllowsColumnReordering:NO];
    [mModsTableView setAllowsMultipleSelection:NO];
    [mModsTableView setDataSource:(id)self];
    [mModsTableView setDelegate:(id)self];
    [mModsTableScrollView setDocumentView:mModsTableView];
    [installedView addSubview:mModsTableScrollView];
    [installedTab setView:installedView];
    [mModsTabView addTabViewItem:installedTab];

    NSTabViewItem* pluginsTab = [[[NSTabViewItem alloc] initWithIdentifier:@"plugins"] autorelease];
    [pluginsTab setLabel:@"Plugins"];
    NSView* pluginsView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 206)] autorelease];
    [pluginsView addSubview:[self label:@"Plugin load order for active plugin-based mods" frame:NSMakeRect(0, 184, 330, 20)]];
    mContentTableScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 720, 178)] autorelease];
    [mContentTableScrollView setHasVerticalScroller:YES];
    [mContentTableScrollView setHasHorizontalScroller:YES];
    [mContentTableScrollView setBorderType:NSBezelBorder];

    mContentTableView = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 720, 178)] autorelease];
    NSTableColumn* enabledColumn = [[[NSTableColumn alloc] initWithIdentifier:@"enabled"] autorelease];
    [enabledColumn setWidth:44];
    [[enabledColumn headerCell] setStringValue:@"On"];
    NSButtonCell* checkboxCell = [[[NSButtonCell alloc] init] autorelease];
    [checkboxCell setButtonType:NSSwitchButton];
    [checkboxCell setTitle:@""];
    [checkboxCell setImagePosition:NSImageOnly];
    [enabledColumn setDataCell:checkboxCell];
    [mContentTableView addTableColumn:enabledColumn];

    NSTableColumn* contentColumn = [[[NSTableColumn alloc] initWithIdentifier:@"content"] autorelease];
    [contentColumn setWidth:660];
    [[contentColumn headerCell] setStringValue:@"Plugin / Content File"];
    [mContentTableView addTableColumn:contentColumn];

    [mContentTableView setUsesAlternatingRowBackgroundColors:YES];
    [mContentTableView setAllowsColumnReordering:NO];
    [mContentTableView setAllowsMultipleSelection:NO];
    [mContentTableView setDataSource:(id)self];
    [mContentTableView setDelegate:(id)self];
    [mContentTableView registerForDraggedTypes:[NSArray arrayWithObject:@"OpenMWContentRow"]];
    [mContentTableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    [mContentTableScrollView setDocumentView:mContentTableView];
    [pluginsView addSubview:mContentTableScrollView];
    [pluginsTab setView:pluginsView];
    [mModsTabView addTabViewItem:pluginsTab];

    [mModsPage addSubview:mModsTabView];
    [mPageContainer addSubview:mModsPage];
}

- (void)buildGraphicsPage
{
    mGraphicsPage = [[[NSView alloc] initWithFrame:[mPageContainer bounds]] autorelease];
    mVideoTabView = [[[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 720, 430)] autorelease];

    NSTabViewItem* displayTab = [[[NSTabViewItem alloc] initWithIdentifier:@"display"] autorelease];
    [displayTab setLabel:@"Display"];
    NSView* displayView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 400)] autorelease];
    [displayView addSubview:[self sectionLabel:@"Display" frame:NSMakeRect(20, 364, 220, 18)]];
    [displayView addSubview:[self label:@"Resolution" frame:NSMakeRect(20, 336, 100, 18)]];
    mResolutionPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 310, 182, 26) pullsDown:NO] autorelease];
    [displayView addSubview:mResolutionPopup];
    [displayView addSubview:[self label:@"Screen" frame:NSMakeRect(240, 336, 100, 18)]];
    mScreenPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(240, 310, 170, 26) pullsDown:NO] autorelease];
    NSInteger screenCount = [[NSScreen screens] count];
    if (screenCount < 1)
        screenCount = 1;
    for (NSInteger i = 0; i < screenCount; ++i)
        [mScreenPopup addItemWithTitle:[NSString stringWithFormat:@"Screen %ld", static_cast<long>(i + 1)]];
    [displayView addSubview:mScreenPopup];
    [mScreenPopup setTarget:self];
    [mScreenPopup setAction:@selector(screenChanged:)];
    [displayView addSubview:[self label:@"Window mode" frame:NSMakeRect(20, 270, 120, 18)]];
    mWindowModePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 244, 190, 26) pullsDown:NO] autorelease];
    [mWindowModePopup addItemWithTitle:@"Fullscreen"];
    [mWindowModePopup addItemWithTitle:@"Borderless Fullscreen"];
    [mWindowModePopup addItemWithTitle:@"Windowed"];
    [displayView addSubview:mWindowModePopup];
    [mWindowModePopup setTarget:self];
    [mWindowModePopup setAction:@selector(refreshGraphicsControlAvailability:)];
    [displayView addSubview:[self label:@"VSync" frame:NSMakeRect(240, 270, 120, 18)]];
    mVsyncPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(240, 244, 170, 26) pullsDown:NO] autorelease];
    [mVsyncPopup addItemWithTitle:@"Disabled"];
    [mVsyncPopup addItemWithTitle:@"Enabled"];
    [mVsyncPopup addItemWithTitle:@"Adaptive"];
    [displayView addSubview:mVsyncPopup];
    [displayView addSubview:[self sectionLabel:@"Startup" frame:NSMakeRect(20, 202, 220, 18)]];
    mWindowBorderCheck = [self checkboxWithTitle:@"Window border" frame:NSMakeRect(20, 170, 150, 20)];
    mSkipMenuCheck = [self checkboxWithTitle:@"Skip menu when launching" frame:NSMakeRect(240, 170, 190, 20)];
    [displayView addSubview:mWindowBorderCheck];
    [displayView addSubview:mSkipMenuCheck];
    [displayView addSubview:[self label:@"Framerate limit" frame:NSMakeRect(20, 138, 120, 18)]];
    mFrameRateField = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 112, 86, 24)] autorelease];
    [displayView addSubview:mFrameRateField];
    [displayView addSubview:[self sectionLabel:@"Advanced" frame:NSMakeRect(20, 80, 220, 18)]];
    [displayView addSubview:[self label:@"Threading mode" frame:NSMakeRect(20, 52, 120, 18)]];
    mThreadingPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 26, 320, 26) pullsDown:NO] autorelease];
    [mThreadingPopup addItemWithTitle:@"Automatic"];
    [mThreadingPopup addItemWithTitle:@"SingleThreaded"];
    [mThreadingPopup addItemWithTitle:@"CullDrawThreadPerContext"];
    [mThreadingPopup addItemWithTitle:@"DrawThreadPerContext"];
    [mThreadingPopup addItemWithTitle:@"CullThreadPerCameraDrawThreadPerContext"];
    [displayView addSubview:mThreadingPopup];
    [displayTab setView:displayView];
    [mVideoTabView addTabViewItem:displayTab];

    NSTabViewItem* renderingTab = [[[NSTabViewItem alloc] initWithIdentifier:@"rendering"] autorelease];
    [renderingTab setLabel:@"Rendering"];
    NSView* renderingView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 400)] autorelease];
    [renderingView addSubview:[self sectionLabel:@"Scene" frame:NSMakeRect(20, 364, 220, 18)]];
    [renderingView addSubview:[self label:@"Lighting method" frame:NSMakeRect(20, 336, 120, 18)]];
    mLightingMethodPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 310, 200, 26) pullsDown:NO] autorelease];
    [mLightingMethodPopup addItemWithTitle:@"Fixed Function"];
    [mLightingMethodPopup addItemWithTitle:@"Per Object"];
    [mLightingMethodPopup addItemWithTitle:@"Single UBO"];
    [renderingView addSubview:mLightingMethodPopup];
    [renderingView addSubview:[self label:@"Viewing distance" frame:NSMakeRect(240, 336, 120, 18)]];
    mViewingDistanceSlider = [[[NSSlider alloc] initWithFrame:NSMakeRect(240, 310, 180, 24)] autorelease];
    [mViewingDistanceSlider setMinValue:2048.0];
    [mViewingDistanceSlider setMaxValue:65536.0];
    [mViewingDistanceSlider setTarget:self];
    [mViewingDistanceSlider setAction:@selector(refreshGraphicsControlAvailability:)];
    [renderingView addSubview:mViewingDistanceSlider];
    mViewingDistanceValueLabel = [self label:@"" frame:NSMakeRect(430, 336, 80, 18)];
    [renderingView addSubview:mViewingDistanceValueLabel];
    [renderingView addSubview:[self label:@"Object paging min size" frame:NSMakeRect(520, 336, 150, 18)]];
    mObjectPagingMinSizeSlider = [[[NSSlider alloc] initWithFrame:NSMakeRect(520, 310, 150, 24)] autorelease];
    [mObjectPagingMinSizeSlider setMinValue:0.01];
    [mObjectPagingMinSizeSlider setMaxValue:1.0];
    [mObjectPagingMinSizeSlider setTarget:self];
    [mObjectPagingMinSizeSlider setAction:@selector(refreshGraphicsControlAvailability:)];
    [renderingView addSubview:mObjectPagingMinSizeSlider];
    mObjectPagingMinSizeValueLabel = [self label:@"" frame:NSMakeRect(520, 286, 80, 18)];
    [renderingView addSubview:mObjectPagingMinSizeValueLabel];
    mDistantTerrainCheck = [self checkboxWithTitle:@"Distant terrain" frame:NSMakeRect(20, 272, 170, 20)];
    mGroundcoverCheck = [self checkboxWithTitle:@"Groundcover" frame:NSMakeRect(240, 272, 170, 20)];
    mSoftParticlesCheck = [self checkboxWithTitle:@"Soft particles" frame:NSMakeRect(420, 272, 170, 20)];
    [renderingView addSubview:mDistantTerrainCheck];
    [renderingView addSubview:mGroundcoverCheck];
    [renderingView addSubview:mSoftParticlesCheck];
    [renderingView addSubview:[self sectionLabel:@"Filtering" frame:NSMakeRect(20, 234, 220, 18)]];
    [renderingView addSubview:[self label:@"Antialiasing" frame:NSMakeRect(20, 206, 120, 18)]];
    mAntialiasingPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 180, 90, 26) pullsDown:NO] autorelease];
    [mAntialiasingPopup addItemWithTitle:@"0"];
    [mAntialiasingPopup addItemWithTitle:@"2"];
    [mAntialiasingPopup addItemWithTitle:@"4"];
    [mAntialiasingPopup addItemWithTitle:@"8"];
    [mAntialiasingPopup addItemWithTitle:@"16"];
    [renderingView addSubview:mAntialiasingPopup];
    [renderingView addSubview:[self label:@"Anisotropy" frame:NSMakeRect(130, 206, 120, 18)]];
    mAnisotropyPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 180, 90, 26) pullsDown:NO] autorelease];
    [mAnisotropyPopup addItemWithTitle:@"0"];
    [mAnisotropyPopup addItemWithTitle:@"1"];
    [mAnisotropyPopup addItemWithTitle:@"2"];
    [mAnisotropyPopup addItemWithTitle:@"4"];
    [mAnisotropyPopup addItemWithTitle:@"8"];
    [mAnisotropyPopup addItemWithTitle:@"16"];
    [renderingView addSubview:mAnisotropyPopup];
    [renderingView addSubview:[self label:@"Texture mag" frame:NSMakeRect(240, 206, 120, 18)]];
    mTextureMagPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(240, 180, 160, 26) pullsDown:NO] autorelease];
    [mTextureMagPopup addItemWithTitle:@"linear"];
    [mTextureMagPopup addItemWithTitle:@"nearest"];
    [renderingView addSubview:mTextureMagPopup];
    [renderingView addSubview:[self label:@"Texture min" frame:NSMakeRect(420, 206, 120, 18)]];
    mTextureMinPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(420, 180, 160, 26) pullsDown:NO] autorelease];
    [mTextureMinPopup addItemWithTitle:@"linear"];
    [mTextureMinPopup addItemWithTitle:@"nearest"];
    [renderingView addSubview:mTextureMinPopup];
    [renderingView addSubview:[self label:@"Texture mipmap" frame:NSMakeRect(20, 142, 120, 18)]];
    mTextureMipmapPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 116, 160, 26) pullsDown:NO] autorelease];
    [mTextureMipmapPopup addItemWithTitle:@"none"];
    [mTextureMipmapPopup addItemWithTitle:@"nearest"];
    [mTextureMipmapPopup addItemWithTitle:@"linear"];
    [renderingView addSubview:mTextureMipmapPopup];
    [renderingView addSubview:[self sectionLabel:@"Streaming" frame:NSMakeRect(20, 78, 220, 18)]];
    mObjectPagingCheck = [self checkboxWithTitle:@"Object paging" frame:NSMakeRect(20, 46, 170, 20)];
    mObjectPagingActiveGridCheck = [self checkboxWithTitle:@"Object paging active grid" frame:NSMakeRect(240, 46, 190, 20)];
    [renderingView addSubview:mObjectPagingCheck];
    [renderingView addSubview:mObjectPagingActiveGridCheck];
    [renderingTab setView:renderingView];
    [mVideoTabView addTabViewItem:renderingTab];

    NSTabViewItem* effectsTab = [[[NSTabViewItem alloc] initWithIdentifier:@"effects"] autorelease];
    [effectsTab setLabel:@"Effects"];
    NSView* effectsView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 400)] autorelease];
    [effectsView addSubview:[self sectionLabel:@"Atmosphere" frame:NSMakeRect(20, 364, 220, 18)]];
    mWeatherOcclusionCheck = [self checkboxWithTitle:@"Weather particle occlusion" frame:NSMakeRect(20, 332, 210, 20)];
    mRadialFogCheck = [self checkboxWithTitle:@"Radial fog" frame:NSMakeRect(20, 300, 140, 20)];
    mExponentialFogCheck = [self checkboxWithTitle:@"Exponential fog" frame:NSMakeRect(180, 300, 160, 20)];
    mSkyBlendingCheck = [self checkboxWithTitle:@"Sky blending" frame:NSMakeRect(360, 300, 140, 20)];
    [effectsView addSubview:mWeatherOcclusionCheck];
    [effectsView addSubview:mRadialFogCheck];
    [effectsView addSubview:mExponentialFogCheck];
    [effectsView addSubview:mSkyBlendingCheck];
    [effectsView addSubview:[self label:@"Sky blend start" frame:NSMakeRect(520, 332, 120, 18)]];
    mSkyBlendingStartField = [[[NSTextField alloc] initWithFrame:NSMakeRect(520, 300, 90, 24)] autorelease];
    [effectsView addSubview:mSkyBlendingStartField];
    [effectsView addSubview:[self sectionLabel:@"Post-Processing" frame:NSMakeRect(20, 252, 220, 18)]];
    mPostProcessingCheck = [self checkboxWithTitle:@"Post-processing" frame:NSMakeRect(20, 220, 170, 20)];
    mTransparentPostpassCheck = [self checkboxWithTitle:@"Transparent postpass" frame:NSMakeRect(200, 220, 170, 20)];
    [effectsView addSubview:mPostProcessingCheck];
    [effectsView addSubview:mTransparentPostpassCheck];
    [effectsView addSubview:[self label:@"HDR exposure speed" frame:NSMakeRect(420, 252, 140, 18)]];
    mPostProcessExposureField = [[[NSTextField alloc] initWithFrame:NSMakeRect(420, 220, 90, 24)] autorelease];
    [effectsView addSubview:mPostProcessExposureField];
    [effectsView addSubview:[self sectionLabel:@"Water" frame:NSMakeRect(20, 170, 220, 18)]];
    mWaterShaderCheck = [self checkboxWithTitle:@"Water shader" frame:NSMakeRect(20, 138, 140, 20)];
    mWaterRefractionCheck = [self checkboxWithTitle:@"Water refraction" frame:NSMakeRect(180, 138, 150, 20)];
    mWaterScatteringCheck = [self checkboxWithTitle:@"Sunlight scattering" frame:NSMakeRect(350, 138, 160, 20)];
    mWaterWobblyCheck = [self checkboxWithTitle:@"Wobbly shores" frame:NSMakeRect(530, 138, 150, 20)];
    [effectsView addSubview:mWaterShaderCheck];
    [effectsView addSubview:mWaterRefractionCheck];
    [effectsView addSubview:mWaterScatteringCheck];
    [effectsView addSubview:mWaterWobblyCheck];
    [effectsView addSubview:[self label:@"Reflection detail" frame:NSMakeRect(20, 98, 120, 18)]];
    mWaterReflectionDetailField = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 72, 90, 24)] autorelease];
    [effectsView addSubview:mWaterReflectionDetailField];
    [effectsTab setView:effectsView];
    [mVideoTabView addTabViewItem:effectsTab];

    NSTabViewItem* shadowsTab = [[[NSTabViewItem alloc] initWithIdentifier:@"shadows"] autorelease];
    [shadowsTab setLabel:@"Shadows"];
    NSView* shadowsView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 400)] autorelease];
    [shadowsView addSubview:[self sectionLabel:@"General" frame:NSMakeRect(20, 364, 220, 18)]];
    mShadowsCheck = [self checkboxWithTitle:@"Enable shadows" frame:NSMakeRect(20, 332, 150, 20)];
    [shadowsView addSubview:mShadowsCheck];
    [shadowsView addSubview:[self label:@"Resolution" frame:NSMakeRect(240, 336, 100, 18)]];
    mShadowResolutionField = [[[NSTextField alloc] initWithFrame:NSMakeRect(240, 310, 90, 24)] autorelease];
    [shadowsView addSubview:mShadowResolutionField];
    [shadowsView addSubview:[self label:@"Distance" frame:NSMakeRect(360, 336, 100, 18)]];
    mShadowDistanceField = [[[NSTextField alloc] initWithFrame:NSMakeRect(360, 310, 90, 24)] autorelease];
    [shadowsView addSubview:mShadowDistanceField];
    [shadowsView addSubview:[self label:@"Fade start" frame:NSMakeRect(480, 336, 100, 18)]];
    mShadowFadeField = [[[NSTextField alloc] initWithFrame:NSMakeRect(480, 310, 90, 24)] autorelease];
    [shadowsView addSubview:mShadowFadeField];
    [shadowsView addSubview:[self label:@"Bounds method" frame:NSMakeRect(20, 272, 120, 18)]];
    mShadowBoundsPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 246, 160, 26) pullsDown:NO] autorelease];
    [mShadowBoundsPopup addItemWithTitle:@"bounds"];
    [mShadowBoundsPopup addItemWithTitle:@"primitives"];
    [mShadowBoundsPopup addItemWithTitle:@"none"];
    [shadowsView addSubview:mShadowBoundsPopup];
    [shadowsView addSubview:[self sectionLabel:@"Casters" frame:NSMakeRect(20, 198, 220, 18)]];
    mActorShadowsCheck = [self checkboxWithTitle:@"Actor shadows" frame:NSMakeRect(20, 166, 150, 20)];
    mPlayerShadowsCheck = [self checkboxWithTitle:@"Player shadows" frame:NSMakeRect(190, 166, 150, 20)];
    mTerrainShadowsCheck = [self checkboxWithTitle:@"Terrain shadows" frame:NSMakeRect(360, 166, 150, 20)];
    mObjectShadowsCheck = [self checkboxWithTitle:@"Object shadows" frame:NSMakeRect(530, 166, 150, 20)];
    mIndoorShadowsCheck = [self checkboxWithTitle:@"Indoor shadows" frame:NSMakeRect(20, 134, 150, 20)];
    [shadowsView addSubview:mActorShadowsCheck];
    [shadowsView addSubview:mPlayerShadowsCheck];
    [shadowsView addSubview:mTerrainShadowsCheck];
    [shadowsView addSubview:mObjectShadowsCheck];
    [shadowsView addSubview:mIndoorShadowsCheck];
    [shadowsTab setView:shadowsView];
    [mVideoTabView addTabViewItem:shadowsTab];

    [mGraphicsPage addSubview:mVideoTabView];
    [mPageContainer addSubview:mGraphicsPage];
    [self populateResolutionPopup];
    [self refreshGraphicsControlAvailability:nil];
}

- (NSButton*)checkboxWithTitle:(NSString*)title frame:(NSRect)frame
{
    NSButton* button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setButtonType:NSSwitchButton];
    [button setTitle:title];
    [button setTarget:self];
    [button setAction:@selector(refreshGraphicsControlAvailability:)];
    return button;
}

- (NSTextField*)sectionLabel:(NSString*)text frame:(NSRect)frame
{
    NSTextField* field = [self label:text frame:frame];
    [field setFont:[NSFont boldSystemFontOfSize:12.0]];
    return field;
}

- (void)populateResolutionPopup
{
    [mResolutionPopup removeAllItems];

    NSArray* screens = [NSScreen screens];
    NSInteger selectedScreen = [mScreenPopup indexOfSelectedItem];
    if (selectedScreen < 0 || selectedScreen >= static_cast<NSInteger>([screens count]))
        selectedScreen = 0;

    if ([screens count] == 0)
    {
        [mResolutionPopup addItemWithTitle:@"800 x 600"];
        return;
    }

    NSScreen* screen = [screens objectAtIndex:selectedScreen];
    NSNumber* screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
    CGDirectDisplayID displayID = screenNumber ? static_cast<CGDirectDisplayID>([screenNumber unsignedIntValue]) : 0;

    std::set<std::pair<int, int> > modes;
    if (displayID != 0)
    {
        CFArrayRef availableModes = CGDisplayAvailableModes(displayID);
        if (availableModes)
        {
            const CFIndex count = CFArrayGetCount(availableModes);
            for (CFIndex i = 0; i < count; ++i)
            {
                CFDictionaryRef mode = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(availableModes, i));
                if (!mode)
                    continue;

                const void* widthValue = CFDictionaryGetValue(mode, kCGDisplayWidth);
                const void* heightValue = CFDictionaryGetValue(mode, kCGDisplayHeight);
                if (!widthValue || !heightValue)
                    continue;

                int width = 0;
                int height = 0;
                if (CFGetTypeID(widthValue) == CFNumberGetTypeID() && CFGetTypeID(heightValue) == CFNumberGetTypeID()
                    && CFNumberGetValue(static_cast<CFNumberRef>(widthValue), kCFNumberIntType, &width)
                    && CFNumberGetValue(static_cast<CFNumberRef>(heightValue), kCFNumberIntType, &height)
                    && width > 0 && height > 0)
                {
                    modes.insert(std::make_pair(width, height));
                }
            }
        }
    }

    if (modes.empty())
    {
        NSRect frame = [screen frame];
        modes.insert(std::make_pair(static_cast<int>(frame.size.width), static_cast<int>(frame.size.height)));
    }

    std::vector<std::pair<int, int> > orderedModes(modes.begin(), modes.end());
    std::sort(orderedModes.begin(), orderedModes.end(), std::greater<std::pair<int, int> >());

    for (std::vector<std::pair<int, int> >::const_iterator it = orderedModes.begin(); it != orderedModes.end(); ++it)
    {
        NSString* title = [NSString stringWithFormat:@"%d x %d", it->first, it->second];
        [mResolutionPopup addItemWithTitle:title];
    }

    NSString* currentTitle = [NSString stringWithFormat:@"%d x %d", mModel.resolutionX, mModel.resolutionY];
    if ([mResolutionPopup itemWithTitle:currentTitle] == nil)
        [mResolutionPopup addItemWithTitle:currentTitle];
    [mResolutionPopup selectItemWithTitle:currentTitle];
}

- (void)screenChanged:(id)sender
{
    (void)sender;
    [self populateResolutionPopup];
    [self refreshGraphicsControlAvailability:nil];
}

- (void)refreshGraphicsControlAvailability:(id)sender
{
    (void)sender;

    const BOOL windowed = [mWindowModePopup indexOfSelectedItem] == static_cast<NSInteger>(Settings::WindowMode::Windowed);
    const BOOL objectPaging = [mObjectPagingCheck state] == NSOnState;
    const BOOL postProcessing = [mPostProcessingCheck state] == NSOnState;
    const BOOL skyBlending = [mSkyBlendingCheck state] == NSOnState;
    const BOOL waterShader = [mWaterShaderCheck state] == NSOnState;
    const BOOL shadows = [mShadowsCheck state] == NSOnState;

    [mWindowBorderCheck setEnabled:windowed];

    [mObjectPagingActiveGridCheck setEnabled:objectPaging];
    [mObjectPagingMinSizeSlider setEnabled:objectPaging];

    [mTransparentPostpassCheck setEnabled:postProcessing];
    [mPostProcessExposureField setEnabled:postProcessing];

    [mSkyBlendingStartField setEnabled:skyBlending];

    [mWaterRefractionCheck setEnabled:waterShader];
    [mWaterScatteringCheck setEnabled:waterShader];
    [mWaterWobblyCheck setEnabled:waterShader];
    [mWaterReflectionDetailField setEnabled:waterShader];

    [mActorShadowsCheck setEnabled:shadows];
    [mPlayerShadowsCheck setEnabled:shadows];
    [mTerrainShadowsCheck setEnabled:shadows];
    [mObjectShadowsCheck setEnabled:shadows];
    [mIndoorShadowsCheck setEnabled:shadows];
    [mShadowResolutionField setEnabled:shadows];
    [mShadowDistanceField setEnabled:shadows];
    [mShadowFadeField setEnabled:shadows];
    [mShadowBoundsPopup setEnabled:shadows];

    [self refreshGraphicsValueLabels];
}

- (void)refreshGraphicsValueLabels
{
    [mViewingDistanceValueLabel setStringValue:[NSString stringWithFormat:@"%d",
                                                                      static_cast<int>([mViewingDistanceSlider doubleValue])]];
    [mObjectPagingMinSizeValueLabel setStringValue:[NSString stringWithFormat:@"%.2f",
                                                                           [mObjectPagingMinSizeSlider doubleValue]]];
}

- (void)showPageAtIndex:(NSInteger)index
{
    Log(Debug::Info) << "Launcher-Cocoa: showPageAtIndex " << static_cast<int>(index);
    [mDataPage setHidden:index != 0];
    [mModsPage setHidden:index != 1];
    [mGraphicsPage setHidden:index != 2];
}

- (void)changePage:(id)sender
{
    [self showPageAtIndex:[mPageSelector selectedSegment]];
    (void)sender;
}

- (void)loadModelIntoControls
{
    [self refreshScannedData];
    if ([mScreenPopup numberOfItems] > 0)
        [mScreenPopup selectItemAtIndex:std::min<NSInteger>(mModel.screen, [mScreenPopup numberOfItems] - 1)];
    [self populateResolutionPopup];
    [mWindowModePopup selectItemAtIndex:static_cast<NSInteger>(mModel.windowMode)];
    [mVsyncPopup selectItemAtIndex:static_cast<NSInteger>(mModel.vsyncMode)];
    selectPopupByValue(mThreadingPopup, mModel.threadingMode.empty() ? "Automatic" : mModel.threadingMode);
    [mWindowBorderCheck setState:mModel.windowBorder ? NSOnState : NSOffState];
    [mFrameRateField setStringValue:toNSString(std::to_string(mModel.frameRateLimit))];
    NSString* antialiasingTitle = toNSString(std::to_string(mModel.antialiasing));
    if ([mAntialiasingPopup itemWithTitle:antialiasingTitle] == nil)
        [mAntialiasingPopup addItemWithTitle:antialiasingTitle];
    [mAntialiasingPopup selectItemWithTitle:antialiasingTitle];
    NSString* anisotropyTitle = toNSString(std::to_string(mModel.anisotropy));
    if ([mAnisotropyPopup itemWithTitle:anisotropyTitle] == nil)
        [mAnisotropyPopup addItemWithTitle:anisotropyTitle];
    [mAnisotropyPopup selectItemWithTitle:anisotropyTitle];
    [mViewingDistanceSlider setDoubleValue:mModel.viewingDistance];
    [mObjectPagingMinSizeSlider setDoubleValue:mModel.objectPagingMinSize];
    [mWaterReflectionDetailField setStringValue:toNSString(std::to_string(mModel.waterReflectionDetail))];
    [mPostProcessExposureField setStringValue:toNSString(std::to_string(mModel.postProcessExposureSpeed))];
    [mSkyBlendingStartField setStringValue:toNSString(std::to_string(mModel.skyBlendingStart))];
    [mShadowDistanceField setStringValue:toNSString(std::to_string(mModel.shadowDistance))];
    [mShadowFadeField setStringValue:toNSString(std::to_string(mModel.shadowFadeStart))];
    [mShadowResolutionField setStringValue:toNSString(std::to_string(mModel.shadowMapResolution))];
    selectPopupByValue(mTextureMagPopup, mModel.textureMagFilter);
    selectPopupByValue(mTextureMinPopup, mModel.textureMinFilter);
    selectPopupByValue(mTextureMipmapPopup, mModel.textureMipmap, 1);
    [mLightingMethodPopup selectItemAtIndex:mModel.lightingMethod];
    selectPopupByValue(mShadowBoundsPopup, mModel.shadowComputeSceneBounds);
    [mSkipMenuCheck setState:mModel.skipMenu ? NSOnState : NSOffState];
    [mSoftParticlesCheck setState:mModel.softParticles ? NSOnState : NSOffState];
    [mRadialFogCheck setState:mModel.radialFog ? NSOnState : NSOffState];
    [mExponentialFogCheck setState:mModel.exponentialFog ? NSOnState : NSOffState];
    [mSkyBlendingCheck setState:mModel.skyBlending ? NSOnState : NSOffState];
    [mDistantTerrainCheck setState:mModel.distantTerrain ? NSOnState : NSOffState];
    [mObjectPagingCheck setState:mModel.objectPaging ? NSOnState : NSOffState];
    [mObjectPagingActiveGridCheck setState:mModel.objectPagingActiveGrid ? NSOnState : NSOffState];
    [mGroundcoverCheck setState:mModel.groundcover ? NSOnState : NSOffState];
    [mWeatherOcclusionCheck setState:mModel.weatherParticleOcclusion ? NSOnState : NSOffState];
    [mPostProcessingCheck setState:mModel.postProcessing ? NSOnState : NSOffState];
    [mTransparentPostpassCheck setState:mModel.transparentPostpass ? NSOnState : NSOffState];
    [mShadowsCheck setState:mModel.shadows ? NSOnState : NSOffState];
    [mActorShadowsCheck setState:mModel.actorShadows ? NSOnState : NSOffState];
    [mPlayerShadowsCheck setState:mModel.playerShadows ? NSOnState : NSOffState];
    [mTerrainShadowsCheck setState:mModel.terrainShadows ? NSOnState : NSOffState];
    [mObjectShadowsCheck setState:mModel.objectShadows ? NSOnState : NSOffState];
    [mIndoorShadowsCheck setState:mModel.indoorShadows ? NSOnState : NSOffState];
    [mWaterShaderCheck setState:mModel.waterShader ? NSOnState : NSOffState];
    [mWaterRefractionCheck setState:mModel.waterRefraction ? NSOnState : NSOffState];
    [mWaterScatteringCheck setState:mModel.waterSunlightScattering ? NSOnState : NSOffState];
    [mWaterWobblyCheck setState:mModel.waterWobblyShores ? NSOnState : NSOffState];
    [mModsPathField setStringValue:toNSString(pathToString(mService->getModsPath()))];
    [self refreshGraphicsControlAvailability:nil];
    [self reloadContentTable];
}

- (void)pullControlsIntoModel
{
    [self syncSelectionsToModel];
    int width = 800;
    int height = 600;
    sscanf([[[mResolutionPopup selectedItem] title] UTF8String], "%d x %d", &width, &height);
    mModel.resolutionX = std::max(1, width);
    mModel.resolutionY = std::max(1, height);
    mModel.screen = static_cast<int>([mScreenPopup indexOfSelectedItem]);
    mModel.windowMode = static_cast<Settings::WindowMode>([mWindowModePopup indexOfSelectedItem]);
    mModel.vsyncMode = static_cast<SDLUtil::VSyncMode>([mVsyncPopup indexOfSelectedItem]);
    mModel.threadingMode = fromNSString([[mThreadingPopup selectedItem] title]);
    if (mModel.threadingMode == "Automatic")
        mModel.threadingMode.clear();
    mModel.windowBorder = [mWindowBorderCheck state] == NSOnState;
    mModel.frameRateLimit = std::max(0, atoi([[mFrameRateField stringValue] UTF8String]));
    mModel.antialiasing = std::max(0, atoi([[[mAntialiasingPopup selectedItem] title] UTF8String]));
    mModel.anisotropy = std::max(0, atoi([[[mAnisotropyPopup selectedItem] title] UTF8String]));
    mModel.lightingMethod = static_cast<int>([mLightingMethodPopup indexOfSelectedItem]);
    mModel.viewingDistance = std::max(0.f, static_cast<float>([mViewingDistanceSlider doubleValue]));
    mModel.objectPagingMinSize = std::max(0.f, static_cast<float>([mObjectPagingMinSizeSlider doubleValue]));
    mModel.waterReflectionDetail = std::max(0, atoi([[mWaterReflectionDetailField stringValue] UTF8String]));
    mModel.postProcessExposureSpeed
        = std::max(0.0001f, static_cast<float>(atof([[mPostProcessExposureField stringValue] UTF8String])));
    mModel.skyBlendingStart
        = std::max(0.f, std::min(1.f, static_cast<float>(atof([[mSkyBlendingStartField stringValue] UTF8String]))));
    mModel.shadowDistance = std::max(0.f, static_cast<float>(atof([[mShadowDistanceField stringValue] UTF8String])));
    mModel.shadowFadeStart
        = std::max(0.f, std::min(1.f, static_cast<float>(atof([[mShadowFadeField stringValue] UTF8String]))));
    mModel.shadowMapResolution = std::max(0, atoi([[mShadowResolutionField stringValue] UTF8String]));
    mModel.textureMagFilter = fromNSString([[mTextureMagPopup selectedItem] title]);
    mModel.textureMinFilter = fromNSString([[mTextureMinPopup selectedItem] title]);
    mModel.textureMipmap = fromNSString([[mTextureMipmapPopup selectedItem] title]);
    mModel.shadowComputeSceneBounds = fromNSString([[mShadowBoundsPopup selectedItem] title]);
    mModel.skipMenu = [mSkipMenuCheck state] == NSOnState;
    mModel.softParticles = [mSoftParticlesCheck state] == NSOnState;
    mModel.radialFog = [mRadialFogCheck state] == NSOnState;
    mModel.exponentialFog = [mExponentialFogCheck state] == NSOnState;
    mModel.skyBlending = [mSkyBlendingCheck state] == NSOnState;
    mModel.distantTerrain = [mDistantTerrainCheck state] == NSOnState;
    mModel.objectPaging = [mObjectPagingCheck state] == NSOnState;
    mModel.objectPagingActiveGrid = [mObjectPagingActiveGridCheck state] == NSOnState;
    mModel.groundcover = [mGroundcoverCheck state] == NSOnState;
    mModel.weatherParticleOcclusion = [mWeatherOcclusionCheck state] == NSOnState;
    mModel.postProcessing = [mPostProcessingCheck state] == NSOnState;
    mModel.transparentPostpass = [mTransparentPostpassCheck state] == NSOnState;
    mModel.shadows = [mShadowsCheck state] == NSOnState;
    mModel.actorShadows = [mActorShadowsCheck state] == NSOnState;
    mModel.playerShadows = [mPlayerShadowsCheck state] == NSOnState;
    mModel.terrainShadows = [mTerrainShadowsCheck state] == NSOnState;
    mModel.objectShadows = [mObjectShadowsCheck state] == NSOnState;
    mModel.indoorShadows = [mIndoorShadowsCheck state] == NSOnState;
    mModel.waterShader = [mWaterShaderCheck state] == NSOnState;
    mModel.waterRefraction = [mWaterRefractionCheck state] == NSOnState;
    mModel.waterSunlightScattering = [mWaterScatteringCheck state] == NSOnState;
    mModel.waterWobblyShores = [mWaterWobblyCheck state] == NSOnState;
}

- (void)setStatus:(const std::string&)text
{
    [mStatusField setStringValue:toNSString(text)];
}

- (void)reload:(id)sender
{
    (void)sender;
    Log(Debug::Info) << "Launcher-Cocoa: reload";
    mModel = mService->load();
    [self loadModelIntoControls];
    [self setStatus:"Reloaded launcher state."];
}

- (void)refreshScannedData
{
    std::vector<std::string> scannedContentFiles;
    mService->scanDataDirectories(mModel.dataDirs, mDetectedArchives, scannedContentFiles);
    mInstalledMods.clear();

    std::error_code ec;
    const std::filesystem::path modsPath = mService->getModsPath();
    if (std::filesystem::exists(modsPath))
    {
        for (std::filesystem::directory_iterator it(modsPath, ec); !ec && it != std::filesystem::directory_iterator();
             it.increment(ec))
        {
            if (!it->is_directory(ec))
                continue;

            InstalledModInfo mod;
            mod.rootPath = pathToString(it->path());
            mod.dataPath = pathToString(installedModDataPath(it->path()));
            mod.name = it->path().filename().string();
            mod.active = std::find(mModel.dataDirs.begin(), mModel.dataDirs.end(), mod.dataPath) != mModel.dataDirs.end();
            mInstalledMods.push_back(mod);
        }
    }

    if (mModel.archives.empty())
        mModel.archives = mDetectedArchives;
    else
        sortUnique(mModel.archives);

    if (mModel.contentFiles.empty() && !scannedContentFiles.empty())
        mModel.contentFiles = scannedContentFiles;
    else if (!scannedContentFiles.empty())
    {
        std::vector<std::string> kept;
        for (std::vector<std::string>::const_iterator it = mModel.contentFiles.begin(); it != mModel.contentFiles.end(); ++it)
        {
            if (std::find(scannedContentFiles.begin(), scannedContentFiles.end(), *it) != scannedContentFiles.end())
                kept.push_back(*it);
        }
        mModel.contentFiles = kept;
    }

    std::vector<std::string> previousOrder = mDetectedContentFiles;
    mDetectedContentFiles.clear();
    for (std::vector<std::string>::const_iterator it = previousOrder.begin(); it != previousOrder.end(); ++it)
    {
        if (std::find(scannedContentFiles.begin(), scannedContentFiles.end(), *it) != scannedContentFiles.end())
            mDetectedContentFiles.push_back(*it);
    }
    for (std::vector<std::string>::const_iterator it = scannedContentFiles.begin(); it != scannedContentFiles.end(); ++it)
    {
        if (std::find(mDetectedContentFiles.begin(), mDetectedContentFiles.end(), *it) == mDetectedContentFiles.end())
            mDetectedContentFiles.push_back(*it);
    }
    [mModsPathField setStringValue:toNSString(pathToString(mService->getModsPath()))];
    [self reloadDataDirsTable];
    [self reloadModsTable];
    [self reloadContentTable];
}

- (void)reloadDataDirsTable
{
    [mDataDirsTableView reloadData];
}

- (void)reloadModsTable
{
    [mModsTableView reloadData];
}

- (void)syncSelectionsToModel
{
    std::vector<std::string> enabled = mModel.contentFiles;
    mModel.contentFiles.clear();
    for (std::size_t i = 0; i < mDetectedContentFiles.size(); ++i)
    {
        if (std::find(enabled.begin(), enabled.end(), mDetectedContentFiles[i]) != enabled.end())
            mModel.contentFiles.push_back(mDetectedContentFiles[i]);
    }
}

- (void)reloadContentTable
{
    [mContentTableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    if (tableView == mDataDirsTableView)
        return static_cast<NSInteger>(mModel.dataDirs.size());
    if (tableView == mModsTableView)
        return static_cast<NSInteger>(mInstalledMods.size());
    return static_cast<NSInteger>(mDetectedContentFiles.size());
}

- (id)tableView:(NSTableView*)tableView objectValueForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    if (tableView == mDataDirsTableView)
    {
        if (row < 0 || row >= static_cast<NSInteger>(mModel.dataDirs.size()))
            return nil;
        return toNSString(mModel.dataDirs[row]);
    }

    if (tableView == mModsTableView)
    {
        if (row < 0 || row >= static_cast<NSInteger>(mInstalledMods.size()))
            return nil;
        const InstalledModInfo& mod = mInstalledMods[row];
        if ([[tableColumn identifier] isEqualToString:@"modEnabled"])
            return [NSNumber numberWithInt:mod.active ? NSOnState : NSOffState];
        if ([[tableColumn identifier] isEqualToString:@"modName"])
            return toNSString(mod.name);
        return toNSString(mod.dataPath);
    }

    if (row < 0 || row >= static_cast<NSInteger>(mDetectedContentFiles.size()))
        return nil;
    const std::string& name = mDetectedContentFiles[row];
    if ([[tableColumn identifier] isEqualToString:@"enabled"])
    {
        const bool enabled = std::find(mModel.contentFiles.begin(), mModel.contentFiles.end(), name) != mModel.contentFiles.end();
        return [NSNumber numberWithInt:enabled ? NSOnState : NSOffState];
    }
    return toNSString(name);
}

- (void)tableView:(NSTableView*)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    if (tableView == mDataDirsTableView)
        return;

    if (tableView == mModsTableView)
    {
        if (![[tableColumn identifier] isEqualToString:@"modEnabled"] || row < 0
            || row >= static_cast<NSInteger>(mInstalledMods.size()))
            return;

        const InstalledModInfo& mod = mInstalledMods[row];
        const bool enable = [object intValue] == NSOnState;
        std::vector<std::string>::iterator it = std::find(mModel.dataDirs.begin(), mModel.dataDirs.end(), mod.dataPath);
        if (enable)
        {
            if (it == mModel.dataDirs.end())
                mModel.dataDirs.push_back(mod.dataPath);
        }
        else if (it != mModel.dataDirs.end())
        {
            mModel.dataDirs.erase(it);
        }
        [self refreshScannedData];
        return;
    }

    if (![[tableColumn identifier] isEqualToString:@"enabled"] || row < 0
        || row >= static_cast<NSInteger>(mDetectedContentFiles.size()))
        return;

    const std::string name = mDetectedContentFiles[row];
    const bool enable = [object intValue] == NSOnState;
    std::vector<std::string>::iterator it = std::find(mModel.contentFiles.begin(), mModel.contentFiles.end(), name);
    if (enable)
    {
        if (it == mModel.contentFiles.end())
            mModel.contentFiles.push_back(name);
        [self syncSelectionsToModel];
    }
    else if (it != mModel.contentFiles.end())
    {
        mModel.contentFiles.erase(it);
    }

    [self reloadContentTable];
}

- (BOOL)tableView:(NSTableView*)tableView writeRowsWithIndexes:(NSIndexSet*)rows toPasteboard:(NSPasteboard*)pasteboard
{
    NSInteger row = [rows firstIndex];
    if (tableView == mDataDirsTableView)
    {
        if (row < 0 || row >= static_cast<NSInteger>(mModel.dataDirs.size()))
            return NO;

        [pasteboard declareTypes:[NSArray arrayWithObject:@"OpenMWDataDirRow"] owner:nil];
        [pasteboard setString:[NSString stringWithFormat:@"%ld", static_cast<long>(row)] forType:@"OpenMWDataDirRow"];
        return YES;
    }
    if (tableView == mContentTableView)
    {
        if (row < 0 || row >= static_cast<NSInteger>(mDetectedContentFiles.size()))
            return NO;

        [pasteboard declareTypes:[NSArray arrayWithObject:@"OpenMWContentRow"] owner:nil];
        [pasteboard setString:[NSString stringWithFormat:@"%ld", static_cast<long>(row)] forType:@"OpenMWContentRow"];
        return YES;
    }
    return NO;
}

- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    (void)info;
    if (tableView == mDataDirsTableView)
    {
        if (operation == NSTableViewDropOn)
            [mDataDirsTableView setDropRow:row dropOperation:NSTableViewDropAbove];
        return NSDragOperationMove;
    }
    if (tableView == mContentTableView)
    {
        if (operation == NSTableViewDropOn)
            [mContentTableView setDropRow:row dropOperation:NSTableViewDropAbove];
        return NSDragOperationMove;
    }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    (void)operation;
    NSPasteboard* pasteboard = [info draggingPasteboard];
    if (tableView == mDataDirsTableView)
    {
        NSString* value = [pasteboard stringForType:@"OpenMWDataDirRow"];
        if (!value)
            return NO;

        NSInteger sourceRow = [value integerValue];
        if (sourceRow < 0 || sourceRow >= static_cast<NSInteger>(mModel.dataDirs.size()))
            return NO;

        if (row < 0)
            row = 0;
        if (row > static_cast<NSInteger>(mModel.dataDirs.size()))
            row = static_cast<NSInteger>(mModel.dataDirs.size());
        if (sourceRow == row || sourceRow + 1 == row)
            return NO;

        const std::string item = mModel.dataDirs[sourceRow];
        mModel.dataDirs.erase(mModel.dataDirs.begin() + sourceRow);
        if (row > sourceRow)
            --row;
        mModel.dataDirs.insert(mModel.dataDirs.begin() + row, item);
        [self refreshScannedData];
        [mDataDirsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        return YES;
    }
    if (tableView == mContentTableView)
    {
        NSString* value = [pasteboard stringForType:@"OpenMWContentRow"];
        if (!value)
            return NO;

        NSInteger sourceRow = [value integerValue];
        if (sourceRow < 0 || sourceRow >= static_cast<NSInteger>(mDetectedContentFiles.size()))
            return NO;

        if (row < 0)
            row = 0;
        if (row > static_cast<NSInteger>(mDetectedContentFiles.size()))
            row = static_cast<NSInteger>(mDetectedContentFiles.size());
        if (sourceRow == row || sourceRow + 1 == row)
            return NO;

        const std::string item = mDetectedContentFiles[sourceRow];
        mDetectedContentFiles.erase(mDetectedContentFiles.begin() + sourceRow);
        if (row > sourceRow)
            --row;
        mDetectedContentFiles.insert(mDetectedContentFiles.begin() + row, item);
        [self syncSelectionsToModel];
        [self reloadContentTable];
        return YES;
    }
    return NO;
}

- (void)addDataDirectoryPaths:(NSArray*)paths
{
    bool changed = false;
    for (NSUInteger i = 0; i < [paths count]; ++i)
    {
        NSString* path = [paths objectAtIndex:i];
        std::string value = fromNSString(path);
        if (!value.empty() && std::find(mModel.dataDirs.begin(), mModel.dataDirs.end(), value) == mModel.dataDirs.end())
        {
            mModel.dataDirs.push_back(value);
            changed = true;
        }
    }
    if (changed)
    {
        [self refreshScannedData];
        [self setStatus:"Added data directories."];
    }
}

- (void)removeAllDataDirs:(id)sender
{
    (void)sender;
    mModel.dataDirs.clear();
    mModel.archives.clear();
    mModel.contentFiles.clear();
    [self refreshScannedData];
    [self setStatus:"Cleared data directories."];
}

- (void)deleteSelectedDataDir:(id)sender
{
    (void)sender;
    NSInteger index = [mDataDirsTableView clickedRow];
    if (index < 0)
        index = [mDataDirsTableView selectedRow];
    if (index < 0 || index >= static_cast<NSInteger>(mModel.dataDirs.size()))
        return;

    mModel.dataDirs.erase(mModel.dataDirs.begin() + index);
    [self refreshScannedData];
    [self setStatus:"Removed data directory."];
}

- (void)moveDataDirUp:(id)sender
{
    (void)sender;
    NSInteger index = [mDataDirsTableView selectedRow];
    if (index <= 0 || index >= static_cast<NSInteger>(mModel.dataDirs.size()))
        return;
    std::swap(mModel.dataDirs[index], mModel.dataDirs[index - 1]);
    [self refreshScannedData];
    [mDataDirsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index - 1] byExtendingSelection:NO];
}

- (void)moveDataDirDown:(id)sender
{
    (void)sender;
    NSInteger index = [mDataDirsTableView selectedRow];
    if (index < 0 || index + 1 >= static_cast<NSInteger>(mModel.dataDirs.size()))
        return;
    std::swap(mModel.dataDirs[index], mModel.dataDirs[index + 1]);
    [self refreshScannedData];
    [mDataDirsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index + 1] byExtendingSelection:NO];
}

- (void)handleDroppedPaths:(NSArray*)paths
{
    NSMutableArray* dirs = [NSMutableArray array];
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    for (NSUInteger i = 0; i < [paths count]; ++i)
    {
        NSString* path = [paths objectAtIndex:i];
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir)
            [dirs addObject:path];
    }
    [self addDataDirectoryPaths:dirs];
}

- (void)handleModDroppedPaths:(NSArray*)paths
{
    NSMutableArray* dirs = [NSMutableArray array];
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    std::vector<std::string> installed;

    for (NSUInteger i = 0; i < [paths count]; ++i)
    {
        NSString* path = [paths objectAtIndex:i];
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir)
        {
            [dirs addObject:path];
            continue;
        }

        std::filesystem::path archive(fromNSString(path));
        if (!hasExtension(archive, ".7z") && !hasExtension(archive, ".zip"))
            continue;

        std::string extractedRoot;
        std::string error;
        if (!mService->extractArchive(pathToString(archive), extractedRoot, error))
        {
            [self setStatus:error];
            continue;
        }

        std::filesystem::path extractedPath(extractedRoot);
        std::filesystem::path configPath = findFomodConfigPath(extractedPath);
        std::string installedDir;
        if (!configPath.empty())
        {
            FomodConfig config = parseFomodConfig(configPath);
            if (config.steps.empty() && config.requiredFiles.empty() && config.conditionalPatterns.empty())
            {
                [self setStatus:"Failed to parse FOMOD installer metadata."];
                continue;
            }

            FomodInstallState installState;
            for (std::size_t j = 0; j < mDetectedContentFiles.size(); ++j)
                installState.availableFiles.insert(toLower(mDetectedContentFiles[j]));
            for (std::size_t j = 0; j < mModel.contentFiles.size(); ++j)
                installState.activeFiles.insert(toLower(mModel.contentFiles[j]));

            std::vector<FomodFileEntry> selectedFiles = config.requiredFiles;
            const std::string title
                = config.moduleName.empty() ? archive.stem().string() : config.moduleName;
            bool cancelled = false;

            for (std::size_t stepIndex = 0; stepIndex < config.steps.size() && !cancelled; ++stepIndex)
            {
                const FomodStep& step = config.steps[stepIndex];
                if (!evaluateFomodDependency(step.visible, installState))
                    continue;

                for (std::size_t groupIndex = 0; groupIndex < step.groups.size(); ++groupIndex)
                {
                    const FomodGroup& group = step.groups[groupIndex];
                    const std::string type = toLower(group.type);
                    const bool singleSelect = type == "selectexactlyone" || type == "selectatmostone";
                    const bool requireOne = type == "selectexactlyone" || type == "selectatleastone" || type == "selectall";
                    const bool allowNone = type == "selectatmostone";

                    if (type == "selectall")
                    {
                        for (std::size_t pluginIndex = 0; pluginIndex < group.plugins.size(); ++pluginIndex)
                        {
                            const FomodPlugin& plugin = group.plugins[pluginIndex];
                            selectedFiles.insert(selectedFiles.end(), plugin.files.begin(), plugin.files.end());
                            for (std::size_t flagIndex = 0; flagIndex < plugin.flags.size(); ++flagIndex)
                                installState.flags[plugin.flags[flagIndex].name] = plugin.flags[flagIndex].value;
                        }
                        continue;
                    }

                    if (singleSelect)
                    {
                        int selectedIndex = -1;
                        if (!promptForSingleChoice(title + " - " + step.name, group, allowNone, selectedIndex))
                        {
                            cancelled = true;
                            break;
                        }
                        if (selectedIndex >= 0 && selectedIndex < static_cast<int>(group.plugins.size()))
                        {
                            const FomodPlugin& plugin = group.plugins[selectedIndex];
                            selectedFiles.insert(selectedFiles.end(), plugin.files.begin(), plugin.files.end());
                            for (std::size_t flagIndex = 0; flagIndex < plugin.flags.size(); ++flagIndex)
                                installState.flags[plugin.flags[flagIndex].name] = plugin.flags[flagIndex].value;
                        }
                        continue;
                    }

                    std::vector<int> selectedIndices;
                    if (!promptForMultiChoice(title + " - " + step.name, group, requireOne, selectedIndices))
                    {
                        cancelled = true;
                        break;
                    }
                    for (std::size_t selectionIndex = 0; selectionIndex < selectedIndices.size(); ++selectionIndex)
                    {
                        const int pluginIndex = selectedIndices[selectionIndex];
                        if (pluginIndex < 0 || pluginIndex >= static_cast<int>(group.plugins.size()))
                            continue;
                        const FomodPlugin& plugin = group.plugins[pluginIndex];
                        selectedFiles.insert(selectedFiles.end(), plugin.files.begin(), plugin.files.end());
                        for (std::size_t flagIndex = 0; flagIndex < plugin.flags.size(); ++flagIndex)
                            installState.flags[plugin.flags[flagIndex].name] = plugin.flags[flagIndex].value;
                    }
                }
            }

            if (cancelled)
            {
                [self setStatus:"Cancelled FOMOD installation."];
                continue;
            }

            for (std::size_t patternIndex = 0; patternIndex < config.conditionalPatterns.size(); ++patternIndex)
            {
                const FomodConditionalPattern& pattern = config.conditionalPatterns[patternIndex];
                if (evaluateFomodDependency(pattern.dependencies, installState))
                    selectedFiles.insert(selectedFiles.end(), pattern.files.begin(), pattern.files.end());
            }

            if (selectedFiles.empty())
            {
                [self setStatus:"FOMOD installer selected no files to install."];
                continue;
            }

            std::stable_sort(selectedFiles.begin(), selectedFiles.end(),
                [](const FomodFileEntry& lhs, const FomodFileEntry& rhs) { return lhs.priority < rhs.priority; });

            std::filesystem::path installRoot = extractedPath / "_openmw_fomod";
            std::error_code ec;
            std::filesystem::remove_all(installRoot, ec);
            std::filesystem::create_directories(installRoot, ec);
            if (ec)
            {
                [self setStatus:"Failed to create FOMOD install directory."];
                continue;
            }

            bool copyFailed = false;
            for (std::size_t fileIndex = 0; fileIndex < selectedFiles.size(); ++fileIndex)
            {
                if (!copyFomodEntry(extractedPath, installRoot, selectedFiles[fileIndex], error))
                {
                    copyFailed = true;
                    break;
                }
            }
            if (copyFailed)
            {
                [self setStatus:error];
                continue;
            }

            installedDir = pathToString(resolveExtractedDataPath(installRoot));
        }
        else
        {
            installedDir = pathToString(resolveExtractedDataPath(extractedPath));
        }

        installed.push_back(installedDir);
    }

    if (![dirs count] && installed.empty())
    {
        [self setStatus:"No mod folders or .7z archives found in drop."];
        return;
    }

    for (std::size_t i = 0; i < installed.size(); ++i)
        [dirs addObject:toNSString(installed[i])];

    [self addDataDirectoryPaths:dirs];
    if (!installed.empty())
        [self setStatus:"Installed mod archive(s) and updated content list."];
    else
        [self setStatus:"Added mod directories."];
}

- (void)save:(id)sender
{
    (void)sender;
    Log(Debug::Info) << "Launcher-Cocoa: save";
    [self pullControlsIntoModel];
    if (mService->save(mModel))
        [self setStatus:"Saved launcher state."];
    else
        [self setStatus:"Failed to save launcher state."];
}

- (void)launch:(id)sender
{
    (void)sender;
    Log(Debug::Info) << "Launcher-Cocoa: launch button";
    [self pullControlsIntoModel];
    std::string error;
    if (mService->launchOpenMW(mModel, error))
    {
        [self setStatus:"Launched OpenMW."];
        [NSApp terminate:nil];
    }
    else
        [self setStatus:error.empty() ? "Failed to launch OpenMW." : error];
}

@end

int runLauncherCocoa(int argc, char* argv[])
{
    (void)argc;
    (void)argv;

    Files::ConfigurationManager configurationManager;
    initializeConfiguration(configurationManager);
    Debug::setupLogging(configurationManager.getLogPath(), "Launcher-Cocoa");

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    OpenMWCocoaLauncher* delegate = [[[OpenMWCocoaLauncher alloc] init] autorelease];
    [NSApp setDelegate:delegate];
    Log(Debug::Info) << "Launcher-Cocoa: entering NSApp run";
    [NSApp run];
    Log(Debug::Info) << "Launcher-Cocoa: NSApp run returned";
    [pool drain];
    Log(Debug::Info) << "Launcher-Cocoa: pool drained";
    return 0;
}

int main(int argc, char* argv[])
{
    return Debug::wrapApplication(runLauncherCocoa, argc, argv, "Launcher-Cocoa");
}
