import importlib.util
from pathlib import Path
import unittest
from urllib.parse import urlparse

spec = importlib.util.spec_from_file_location(
    "check_flux_helm_values", Path(__file__).with_name("check-flux-helm-values.py")
)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class DomainSubstitutionTests(unittest.TestCase):
    def test_nested_callback_urls_are_valid_without_private_domain(self):
        values = {
            "clients": [{"redirect_uris": ["https://ha.${SECRET_DOMAIN}/auth/openid/callback"]}],
            "smtp": {"address": "submission://mail.${SECRET_DOMAIN}:587"},
        }
        result = hook.substitute_domain(values)
        callback = result["clients"][0]["redirect_uris"][0]
        self.assertEqual(urlparse(callback).hostname, "ha.example.invalid")
        self.assertEqual(urlparse(callback).path, "/auth/openid/callback")
        self.assertEqual(urlparse(result["smtp"]["address"]).port, 587)

    def test_other_substitutions_and_schema_value_types_are_not_rewritten(self):
        values = {"secret": "${OTHER_SECRET}", "port": 587, "enabled": False, "optional": None}
        result = hook.substitute_domain(values)
        self.assertEqual(result["secret"], "${OTHER_SECRET}")
        self.assertIs(type(result["port"]), int)
        self.assertIs(result["enabled"], False)
        self.assertIsNone(result["optional"])


if __name__ == "__main__":
    unittest.main()
