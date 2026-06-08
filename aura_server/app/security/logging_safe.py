"""個人情報を含まないログヘルパー。"""

import logging

logger = logging.getLogger("auraface_api")


def log_request(event: str, **fields):
    safe = {k: v for k, v in fields.items() if v is not None}
    logger.info("%s %s", event, safe)
