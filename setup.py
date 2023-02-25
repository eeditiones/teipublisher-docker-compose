import json
from typing import List, Optional
from jsonschema import validate as json_validate, ValidationError
from pathlib import Path
from jinja2 import FileSystemLoader, Environment
from os import makedirs, rename
import typer
from shutil import rmtree

import yaml

app = typer.Typer()

jinija = Environment(
    loader=FileSystemLoader(searchpath="templates")
)

def load_config(configFile: str) -> dict:
    with open(configFile, 'r') as f:
        data = yaml.load(f, Loader=yaml.FullLoader)
    with open(Path('config-schema.json'), 'r') as f:
        schema = json.load(f)
        try:
            json_validate(data, schema)
            return data
        except ValidationError as e:
            typer.echo(f"Invalid configuration: {e.message}")
            return None

def expand_template(templateFile: str, outputPath: str, config: dict, outputFile: str = None):
    makedirs(outputPath, exist_ok=True)
    typer.echo(f"Copying template {typer.style(str(templateFile), typer.colors.BLUE)}")
    dockerTmpl = jinija.get_template(templateFile)
    output = dockerTmpl.render(config)
    with open(Path(outputPath, templateFile), "w", encoding="UTF-8") as f:
        f.write(output)
    
    if (outputFile != None):
        rename(Path(outputPath, templateFile), Path(outputPath, outputFile))

@app.command()
def clean(
    outDir: Optional[Path] = typer.Option('dist', '--out', '-o', help='Output directory')
):
    rmtree(outDir, ignore_errors=True)

@app.command()
def init(
    configFile: Optional[Path] = typer.Option('config.yml', '--config', '-c', help="Configuration file to use"),
    outDir: Optional[Path] = typer.Option(None, '--out', '-o', help='Output directory'),
    ssl: bool = typer.Option(False, "--ssl")
):
    config = load_config(configFile)
    if (not config):
        return
    typer.echo(config);
    if (ssl):
        config['ssl'] = True
    if (not outDir):
        outDir = config['output_dir'] if 'output_dir' in config else 'dist'
    nginxDir = Path(outDir, 'conf')
    
    expand_template('docker-compose.yml', outDir, config)
    expand_template('default.conf', nginxDir, config)
    expand_template('example.com.conf', nginxDir, config, f"{config['domain']}.conf")
    expand_template('certbot-renew.sh', outDir, config)

if __name__ == "__main__":
    app()