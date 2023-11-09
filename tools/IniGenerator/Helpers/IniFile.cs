using System.Text;
using System.Text.RegularExpressions;
using IniGenerator.Data;

namespace IniGenerator.Helpers;

public class IniFile
{
    private static readonly Regex _sectionPattern = new Regex(@"^\s*\[(?<SectionName>.*)\]\s*([;].*)*\s*$");
    private static readonly Regex _optionsPattern = new Regex(@"^\s*(?<key>[^=]*)=(?<value>[^;]*)\s*([;].*)*\s*$");

    private List<Section> _sections { get; set; } = new List<Section>();
    private List<Option> _options { get; set; } = new List<Option>();

    public static IniFile Create(string fileName)
    {
        var iniFile = new IniFile();
        if (!File.Exists(fileName))
        {
            return iniFile;
        }

        using var inputStream = new FileStream(fileName, FileMode.Open, FileAccess.Read);
        using var streamReader = new StreamReader(inputStream);

        string? line;
        string? currentSection = null;
        while ((line = streamReader.ReadLine()) != null)
        {
            //Handling comments
            if (line.Trim().StartsWith(";"))
            {
                continue;
            }
            else
            {
                Match match = _sectionPattern.Match(line);
                // Handling a new section
                if (match.Success)
                {
                    currentSection = match.Groups["SectionName"].Value;
                }
                else
                {
                    // Might be an option
                    match = _optionsPattern.Match(line);
                    if (match.Success)
                    {
                        iniFile.AddOption(match.Groups["key"].Value, match.Groups["value"].Value, currentSection);
                    }
                }
            }
        }

        return iniFile;
    }

    public void SetOption(string key, string? value, string? section)
    {
        if (section == null)
        {
            var option = _options.FirstOrDefault(o => o.Key == key);
            if (option == null)
            {
                AddOption(key, value, section);
            }
            else
            {
                option.Value = value;
            }
        }
        else
        {
            Section? iniSection = _sections.FirstOrDefault(s => s.Name == section);
            if (iniSection == null)
            {
                AddOption(key, value, section);
            }
            else
            {
                var option = iniSection.Options.FirstOrDefault(o => o.Key == key);
                if(option == null)
                {
                    AddOption(key, value, section);
                }
                else
                {
                    option.Value = value;
                }
            }
        }
    }

    public void AddOption(string key, string? value, string? section = null)
    {
        var newOption = new Option
        {
            Key = key,
            Value = value
        };
        if (section != null)
        {
            Section? iniSection = _sections.FirstOrDefault(s => s.Name == section);
            if (iniSection == null)
            {
                iniSection = new Section
                {
                    Name = section
                };
                _sections.Add(iniSection);
            }
            iniSection.Options.Add(newOption);
        }
        else
        {
            _options.Add(newOption);
        }
    }

    public void SaveAs(string fileName)
    {
        StringBuilder iniBuilder = new StringBuilder();
        foreach (Option option in _options)
        {
            iniBuilder.AppendLine($"{option.Key}={option.Value ?? string.Empty}");
        }
        foreach (Section section in _sections)
        {
            if (!string.IsNullOrWhiteSpace(iniBuilder.ToString()))
            {
                iniBuilder.AppendLine();
            }
            iniBuilder.AppendLine($"[{section.Name}]");
            foreach (Option option in section.Options)
            {
                iniBuilder.AppendLine($"{option.Key}={option.Value ?? string.Empty}");
            }
        }
        var filePath = Path.GetDirectoryName(fileName) ?? 
            throw new DirectoryNotFoundException($"Unknown file path format {fileName}");
        if(!Directory.Exists(filePath))
        {
            Directory.CreateDirectory(filePath);
        }
        File.WriteAllText(fileName, iniBuilder.ToString());
    }
}