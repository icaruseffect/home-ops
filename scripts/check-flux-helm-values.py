"""Run the pinned Flux Helm hook with a non-secret domain for URI validation."""

from copy import deepcopy


def substitute_domain(value):
    if isinstance(value, dict):
        return {key: substitute_domain(item) for key, item in value.items()}
    if isinstance(value, list):
        return [substitute_domain(item) for item in value]
    if isinstance(value, str):
        return value.replace("${SECRET_DOMAIN}", "example.invalid")
    return value


def main():
    from pre_commit_flux import check_flux_helm_values as hook

    original_lint = hook._lint

    def lint(file_to_validate, definition, *args):
        definition = deepcopy(definition)
        if "values" in definition.get("spec", {}):
            definition["spec"]["values"] = substitute_domain(definition["spec"]["values"])
        return original_lint(file_to_validate, definition, *args)

    hook._lint = lint
    return hook.main()


if __name__ == "__main__":
    raise SystemExit(main())
