# HighlightBar.Windows

Native Windows version of the highlight-bar app.

## Run (Windows)

```powershell
dotnet run --project .\HighlightBar.Windows.csproj
```

## Publish (Windows)

```powershell
dotnet publish .\HighlightBar.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\publish\win-x64
```

## Controls

- Tray icon -> context menu
- Font reference size: `10` to `100`
- Opacity: `10%` (most transparent) to `90%` (most solid)
- Color selection + hover preview
- Rounded, outlined bar matching the macOS app

Settings persist to:

`%APPDATA%\HighlightBar\settings.json`
