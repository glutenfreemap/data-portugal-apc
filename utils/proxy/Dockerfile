FROM mcr.microsoft.com/dotnet/sdk:9.0 AS backend
WORKDIR /src
COPY ./proxy.csproj .
RUN dotnet restore "./proxy.csproj"
COPY ./ ./
RUN dotnet publish "./proxy.csproj" -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 8080
COPY --from=backend /app /app
USER $APP_UID
ENTRYPOINT ["dotnet", "proxy.dll"]
