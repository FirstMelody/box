from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "box" / "scripts" / "box.iptables"
SETTINGS = Path(__file__).resolve().parents[1] / "box" / "settings.ini"


def read_script() -> str:
    return SCRIPT.read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    marker = f"{name}() {{"
    start = source.index(marker)
    depth = 0
    for index in range(start, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    raise AssertionError(f"function {name} was not closed")


def assert_order(body: str, *needles: str) -> None:
    last = -1
    for needle in needles:
        index = body.find(needle)
        assert index != -1, f"missing {needle!r}"
        assert index > last, f"{needle!r} appears out of order"
        last = index


class ForceProxyCidrsTest(unittest.TestCase):
    def test_settings_exposes_generic_force_proxy_cidrs(self):
        settings = SETTINGS.read_text(encoding="utf-8")
        script = read_script()

        self.assertIn("force_proxy_cidrs=()", settings)
        self.assertIn("force_proxy_cidrs6=()", settings)
        self.assertNotIn("tun_force_proxy_cidrs", settings)
        self.assertNotIn("tun_force_proxy_cidrs", script)
        self.assertNotIn("effective_force_proxy_cidrs", script)

    def test_tun_uses_generic_force_proxy_rules_before_bypass(self):
        script = read_script()
        body = function_body(script, "start_tun_bypass")

        assert_order(
            body,
            'append_force_proxy_destination_rules "${pre_chain}" route',
            'append_tun_bypass_destination_rules "${pre_chain}"',
        )
        assert_order(
            body,
            'append_force_proxy_destination_rules "${out_chain}" route',
            'append_tun_bypass_destination_rules "${out_chain}"',
        )

    def test_tproxy_normal_chains_force_cidrs_before_common_bypass_and_uid_rules(self):
        script = read_script()

        external = function_body(script, "setup_tproxy_external_chain")
        assert_order(
            external,
            "append_tproxy_force_proxy_destination_rules BOX_EXTERNAL",
            "append_common_bypass_rules mangle BOX_EXTERNAL",
        )

        local = function_body(script, "setup_tproxy_local_chain")
        assert_order(
            local,
            "append_mark_force_proxy_destination_rules mangle BOX_LOCAL",
            "append_common_bypass_rules mangle BOX_LOCAL",
            "apply_local_proxy_rules mangle BOX_LOCAL mark",
        )

    def test_tproxy_performance_chains_force_cidrs_before_perf_bypass_and_uid_rules(self):
        script = read_script()

        external = function_body(script, "setup_tproxy_perf_external_chain")
        assert_order(
            external,
            "append_tproxy_force_proxy_destination_rules BOX_EXTERNAL",
            'add_perf_chain_jumps mangle BOX_EXTERNAL "${ip_chain}" "${if_chain}"',
        )

        local = function_body(script, "setup_tproxy_perf_local_chain")
        assert_order(
            local,
            "append_mark_force_proxy_destination_rules mangle BOX_LOCAL",
            'add_perf_chain_jumps mangle BOX_LOCAL "${ip_chain}" "${app_chain}"',
        )

    def test_redirect_and_enhance_paths_share_force_proxy_cidrs(self):
        script = read_script()

        redirect_external = function_body(script, "setup_redirect_external_chain")
        assert_order(
            redirect_external,
            "append_redirect_force_proxy_destination_rules BOX_EXTERNAL",
            "append_common_bypass_rules nat BOX_EXTERNAL",
        )

        redirect_local = function_body(script, "setup_redirect_local_chain")
        assert_order(
            redirect_local,
            "append_redirect_force_proxy_destination_rules BOX_LOCAL",
            "append_common_bypass_rules nat BOX_LOCAL",
            "apply_local_proxy_rules nat BOX_LOCAL redirect",
        )

        redirect_perf_external = function_body(script, "setup_redirect_perf_external_chain")
        assert_order(
            redirect_perf_external,
            "append_redirect_force_proxy_destination_rules BOX_EXTERNAL",
            'add_perf_chain_jumps nat BOX_EXTERNAL "${ip_chain}" "${if_chain}"',
        )

        redirect_perf_local = function_body(script, "setup_redirect_perf_local_chain")
        assert_order(
            redirect_perf_local,
            "append_redirect_force_proxy_destination_rules BOX_LOCAL",
            'add_perf_chain_jumps nat BOX_LOCAL "${app_chain}" "${ip_chain}"',
        )


if __name__ == "__main__":
    unittest.main()
