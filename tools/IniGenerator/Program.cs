using IniGenerator;
using IniGenerator.Data;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

IHostBuilder hostBuilder = Host.CreateDefaultBuilder();

hostBuilder.ConfigureServices((hostContext, services) =>
{
    services.AddOptions<IniConfiguration>()
        .Bind(hostContext.Configuration.GetSection(nameof(IniConfiguration)))
        .ValidateDataAnnotations();

    services.AddScoped<App>();
});

IHost host = hostBuilder.Build();

using var serviceScope = host.Services.CreateScope();
var app = serviceScope.ServiceProvider.GetRequiredService<App>();
app.Run();