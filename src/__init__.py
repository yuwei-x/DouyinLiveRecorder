from .initializer import check_node
from runtime_paths import configure_bundled_runtime, get_resource_path

JS_SCRIPT_PATH = get_resource_path('src', 'javascript')

configure_bundled_runtime()
check_node()
