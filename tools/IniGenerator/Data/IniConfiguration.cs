using System.ComponentModel.DataAnnotations;

namespace IniGenerator.Data;

public class IniConfiguration
{
    [Required]
    public required string EnvironmentPrefix { get; set; }
    [Required]
    public required string IniFilesPath { get; set; }
}