# Highlight Bar (macOS + Windows)

This repo contains:

- `HighlightBar/` - macOS Swift menu-bar app (already working)
- `WindowsHighlightBar/` - Windows native C# WinForms app

## Windows App Features

- Always-on-top transparent highlight bar
- Click-through overlay so normal app clicks still work
- Follows mouse across screens
- Tray menu controls:
  - font-size reference (`10` to `100`)
  - transparency
  - color
- Remembers last-used settings

## Downloads For Friends

- Windows: from the artifact in **Build Windows App** or from GitHub Releases (`HighlightBar-windows-x64.zip`).
- macOS: from the artifact in **Build macOS App** or from GitHub Releases (`HighlightBar-macos.zip`).

## GitHub Setup (Recommended)

1. Create a new **public** GitHub repository (web UI).
2. In this folder, run:

```bash
git add .
git commit -m "Initial macOS and Windows highlight bar apps"
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin main
```

3. Open your repo on GitHub and go to `Actions`.
4. Run **Build Windows App** (or push to `main`) to produce a downloadable Windows zip artifact.
5. Run **Build macOS App** (or push to `main`) to produce a downloadable macOS zip artifact.
6. To create public Release downloads, tag and push:

```bash
git tag v0.1.0
git push origin v0.1.0
```

That triggers:

- **Release Windows App** -> `HighlightBar-windows-x64.zip`
- **Release macOS App** -> `HighlightBar-macos.zip`

## Local Windows Build (on a Windows machine)

```powershell
cd WindowsHighlightBar
dotnet publish .\HighlightBar.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\publish\win-x64
```

The executable will be in `WindowsHighlightBar\publish\win-x64`.

## Notes

- This environment does not have `.NET` installed, so the Windows app scaffold is prepared but not compiled locally here.
- CI in GitHub Actions will compile it on `windows-latest`.
