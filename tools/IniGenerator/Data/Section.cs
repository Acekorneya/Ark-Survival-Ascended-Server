using System.ComponentModel.DataAnnotations;

namespace IniGenerator.Data;

public class Section
{
    [Required]
    public required string Name { get; set; }
    public List<Option> Options { get; set; } = new List<Option>();
}