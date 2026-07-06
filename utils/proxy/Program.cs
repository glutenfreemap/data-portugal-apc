AppContext.SetSwitch("System.Net.Http.EnableActivityPropagation", false);

var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

app.MapGet("/tp", async () =>
{
    using var client = new HttpClient();
    client.DefaultRequestHeaders.Add("User-Agent", "GlutenFreeMap (glutenfreemap@aaubry.net)");
    client.DefaultRequestHeaders.Add("Referer", "https://glutenfreemap.org");

    var response = await client.GetStringAsync("https://www.telepizza.pt/pizzas-sem-gluten.html");
    return response;
});

app.Run();
