"""Override CONFIG_HTTPD_MAX_REQ_HDR_LEN which web_server_idf hardcodes to 1024."""

import esphome.config_validation as cv
from esphome.components.esp32 import add_idf_sdkconfig_option
from esphome.coroutine import CoroPriority, coroutine_with_priority

CONF_MAX_HEADER_LEN = "max_header_length"

CONFIG_SCHEMA = cv.Schema(
    {
        cv.Optional(CONF_MAX_HEADER_LEN, default=4096): cv.int_range(
            min=512, max=16384
        ),
    }
)

DEPENDENCIES = ["web_server"]


@coroutine_with_priority(CoroPriority.LATE)
async def to_code(config):
    add_idf_sdkconfig_option(
        "CONFIG_HTTPD_MAX_REQ_HDR_LEN", config[CONF_MAX_HEADER_LEN]
    )
