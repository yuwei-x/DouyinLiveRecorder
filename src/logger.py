# -*- coding: utf-8 -*-

import os
import sys
from loguru import logger
from runtime_paths import ensure_user_data_files, is_packaged_macos

logger.remove()

custom_format = "<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | <level>{level: <8}</level> - <level>{message}</level>"
logger_enqueue = not is_packaged_macos()

logger.add(
    sink=sys.stderr,
    format=custom_format,
    level="DEBUG",
    colorize=True,
    enqueue=logger_enqueue
)

script_path = str(ensure_user_data_files())

logger.add(
    f"{script_path}/logs/streamget.log",
    level="DEBUG",
    format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {level: <8} | {name}:{function}:{line} - {message}",
    filter=lambda i: i["level"].name != "INFO",
    serialize=False,
    enqueue=logger_enqueue,
    retention=1,
    rotation="300 KB",
    encoding='utf-8'
)

logger.add(
    f"{script_path}/logs/PlayURL.log",
    level="INFO",
    format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {message}",
    filter=lambda i: i["level"].name == "INFO",
    serialize=False,
    enqueue=logger_enqueue,
    retention=1,
    rotation="300 KB",
    encoding='utf-8'
)
