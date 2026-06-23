# -*- mode: python ; coding: utf-8 -*-

import os
import sys
from pathlib import Path
from PyInstaller.utils.hooks import collect_submodules
from PyInstaller.building.api import COLLECT

block_cipher = None

_HERE = Path.cwd().resolve()                     # backend/
_REPO_ROOT = _HERE.parent                        # repo root (parent of backend/)

# ── Packages with dynamic imports (lazy-loaded submodules) ──────────────
transformers_hidden = collect_submodules('transformers')
sentence_transformers_hidden = collect_submodules('sentence_transformers')
uvicorn_hidden = collect_submodules('uvicorn')
fastapi_hidden = collect_submodules('fastapi')
starlette_hidden = collect_submodules('starlette')
pydantic_hidden = collect_submodules('pydantic')
sqlalchemy_hidden = collect_submodules('sqlalchemy')
anyio_hidden = collect_submodules('anyio')

a = Analysis(
    ['main.py'],
    pathex=[
        str(_REPO_ROOT),
    ],
    binaries=[],
    datas=[
        ('config.yaml', '.'),
        ('alembic.ini', '.'),
        ('db/migrations', 'db/migrations'),
    ],
    hiddenimports=[
        'uvicorn',
        'uvicorn.loops',
        'uvicorn.loops.auto',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.middleware.proxy_headers',
        'fastapi',
        'fastapi.routing',
        'fastapi.openapi',
        'fastapi.openapi.utils',
        'starlette.applications',
        'starlette.routing',
        'starlette.middleware',
        'starlette.middleware.cors',
        'starlette.responses',
        'starlette.requests',
        'starlette.websockets',
        'pydantic',
        'pydantic.dataclasses',
        'pydantic_settings',
        'python_multipart',
        'multipart',
        'anyio',
        'httptools',
        'websockets',
        'sqlalchemy',
        'sqlalchemy.ext.declarative',
        'sqlalchemy.orm',
        'alembic',
        'alembic.config',
        'alembic.command',
        'alembic.script',
        'alembic.runtime.migration',
        'alembic.autogenerate',
        'zeroconf',
        'zeroconf._services',
        'zeroconf._handlers',
        'torch',
        'torch._C',
        'torch.cpu',
        'torch.serialization',
        'torch.nn',
        'torch.optim',
        'torch.utils',
        'torch.utils.data',
        'transformers',
        'sentence_transformers',
        'langchain',
        'langchain_core',
        'langchain_core.messages',
        'langchain_core.tools',
        'langchain_core.language_models',
        'langchain_core.prompts',
        'langchain_core.runnables',
        'langchain_core.outputs',
        'langchain_core.callbacks',
        'langchain_openai',
        'langchain_huggingface',
        'langchain_community',
        'langchain_community.chat_models',
        'langchain_community.chat_models.llama_cpp',
        'langchain_community.embeddings',
        'langgraph',
        'langgraph.graph',
        'langgraph.prebuilt',
        'langgraph.constants',
        'llama_cpp',
        'prometheus_client',
        'prometheus_client.core',
        'prometheus_client.registry',
        'prometheus_fastapi_instrumentator',
        'psutil',
        'elasticsearch',
        'elasticsearch._async.client',
        'pypdf',
        'pypdfium2',
        'pypdfium2._helpers',
        'docx',
        'docx.document',
        'PIL',
        'PIL.Image',
        'PIL.ImageOps',
        'PIL.ImageDraw',
        'PIL.ImageFont',
        'huggingface_hub',
        'huggingface_hub.hf_api',
        'huggingface_hub.hf_hub_download',
        'huggingface_hub.snapshot_download',
        'huggingface_hub.errors',
        'openai',
        'dotenv',
        'yaml',
        'requests',
        'backend.db.migrations.env',
        'backend.db.migrations.versions.0001_initial',
    ] + transformers_hidden + sentence_transformers_hidden
    + uvicorn_hidden + fastapi_hidden + starlette_hidden
    + pydantic_hidden + sqlalchemy_hidden + anyio_hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],   # IMPORTANT: do NOT exclude any torch.*, unittest, pytest, test
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    exclude_binaries=True,
    name='ainas-backend',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='ainas-backend',
)
