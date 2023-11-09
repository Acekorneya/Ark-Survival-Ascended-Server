using IniGenerator.Data;
using IniGenerator.Helpers;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace IniGenerator;

public class App
{
    private readonly ILogger<App> _logger;
    private readonly IOptions<IniConfiguration> _iniOptions;
    private readonly IConfiguration _config;

    public App(ILogger<App> logger, IOptions<IniConfiguration> iniOptions, IConfiguration config)
    {
        _logger = logger;
        _iniOptions = iniOptions;
        _config = config;
    }

    public void Run()
    {
        var prefixedOptions = _config.GetChildren()
            .Where(x => x.Key.StartsWith(_iniOptions.Value.EnvironmentPrefix));

        foreach (var currentFileSection in prefixedOptions)
        {
            string fileName = currentFileSection.Key.Remove(0, _iniOptions.Value.EnvironmentPrefix.Length) + ".ini";
            var filePath = Path.Join(_iniOptions.Value.IniFilesPath, fileName);
            if (!File.Exists(filePath))
            {
                Directory.CreateDirectory(_iniOptions.Value.IniFilesPath);
                File.Create(filePath).Dispose();
            }
            _logger.LogInformation("Processing file {fileName}", fileName);
            var iniFile = IniFile.Create(filePath);
            foreach (var currentCatSection in currentFileSection.GetChildren())
            {
                _logger.LogInformation("Processing section {sectionsName}", currentCatSection.Key);
                foreach (var currentConfig in currentCatSection.GetChildren())
                {
                    _logger.LogInformation("Settings value {key} to {value}", currentConfig.Key, currentConfig.Value);
                    iniFile.SetOption(currentConfig.Key, currentConfig.Value, currentCatSection.Key);
                }
            }
            iniFile.SaveAs(filePath);
            _logger.LogInformation("Ini file was written at {filePath}", filePath);
        }
    }
}