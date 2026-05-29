import argparse
import json
import os
import subprocess
import uuid

import pandas as pd
from tqdm import tqdm
from tree_sitter import Language, Parser

repo_to_top_folder = {
    "django/django": "django",
    "sphinx-doc/sphinx": "sphinx",
    "scikit-learn/scikit-learn": "scikit-learn",
    "sympy/sympy": "sympy",
    "pytest-dev/pytest": "pytest",
    "matplotlib/matplotlib": "matplotlib",
    "astropy/astropy": "astropy",
    "pydata/xarray": "xarray",
    "mwaskom/seaborn": "seaborn",
    "psf/requests": "requests",
    "pylint-dev/pylint": "pylint",
    "pallets/flask": "flask",
}

_PARSER = None
_MODULE_NODE_TYPES = {
    "module_declaration",
    "interface_declaration",
    "program_declaration",
    "package_declaration",
    "class_declaration",
    "interface_class_declaration",
    "checker_declaration",
    "config_declaration",
    "primitive_declaration",
    "udp_declaration",
}
_FUNC_NODE_TYPES = {
    "function_declaration",
    "task_declaration",
    "function_prototype",
    "task_prototype",
    "method_declaration",
    "method_prototype",
    "class_constructor_declaration",
    "class_constructor_prototype",
}
_VERILOG_EXTENSIONS = {".v", ".sv", ".vh", ".svh"}
_ATTRIBUTE_NODE_TYPES = {"attribute_instance"}
_SIMPLE_IDENTIFIER_NODE_TYPES = {
    "simple_identifier",
    "escaped_identifier",
    "module_identifier",
    "udp_identifier",
}


def _get_verilog_parser():
    global _PARSER
    if _PARSER is None:
        so_path = os.environ.get("TREE_SITTER_VERILOG_SO")
        language_name = os.environ.get("TREE_SITTER_VERILOG_LANGUAGE", "verilog")
        if not so_path:
            raise RuntimeError(
                "TREE_SITTER_VERILOG_SO must point to a tree-sitter-verilog .so file"
            )
        if not os.path.isfile(so_path):
            raise RuntimeError(f"tree-sitter .so not found: {so_path}")
        try:
            language = Language(so_path, language_name)
        except TypeError:
            import ctypes

            symbol = os.environ.get(
                "TREE_SITTER_VERILOG_SYMBOL", f"tree_sitter_{language_name}"
            )
            lib = ctypes.CDLL(so_path)
            try:
                func = getattr(lib, symbol)
            except AttributeError as exc:
                raise RuntimeError(
                    f"tree-sitter language symbol '{symbol}' not found in {so_path}"
                ) from exc
            func.restype = ctypes.c_void_p
            language = Language(func())
        parser = Parser()
        if hasattr(parser, "set_language"):
            parser.set_language(language)
        else:
            parser.language = language
        _PARSER = parser
    return _PARSER


def _node_text(node, source_bytes):
    return source_bytes[node.start_byte : node.end_byte].decode(
        "utf-8", errors="replace"
    )


def _iter_tree(node):
    stack = [node]
    while stack:
        current = stack.pop()
        yield current
        if current.children:
            stack.extend(reversed(current.children))


def _find_child(node, type_set):
    for child in node.children:
        if child.type in type_set:
            return child
    return None


def _find_identifier(node, identifier_types):
    for child in node.children:
        if child.type in _ATTRIBUTE_NODE_TYPES:
            continue
        if child.type in identifier_types:
            return child
    return None


def _name_from_direct(node, source_bytes, identifier_types):
    name_node = _find_identifier(node, identifier_types)
    if name_node is None:
        return None
    return _node_text(name_node, source_bytes).strip()


def _name_from_child(node, source_bytes, child_types, identifier_types):
    child = _find_child(node, child_types)
    if child is None:
        return None
    return _name_from_direct(child, source_bytes, identifier_types)


def _node_key(node):
    return (node.start_byte, node.end_byte, node.type)


def _node_name(node, source_bytes):
    node_type = node.type
    if node_type == "module_declaration":
        return _name_from_child(
            node, source_bytes, {"module_header"}, _SIMPLE_IDENTIFIER_NODE_TYPES
        ) or _name_from_direct(node, source_bytes, _SIMPLE_IDENTIFIER_NODE_TYPES)
    if node_type == "udp_declaration":
        return _name_from_child(
            node,
            source_bytes,
            {"udp_nonansi_declaration", "udp_ansi_declaration"},
            _SIMPLE_IDENTIFIER_NODE_TYPES,
        ) or _name_from_direct(node, source_bytes, _SIMPLE_IDENTIFIER_NODE_TYPES)
    if node_type == "interface_declaration":
        name = _name_from_direct(node, source_bytes, {"interface_identifier"})
        if name:
            return name
        return _name_from_child(
            node,
            source_bytes,
            {"interface_nonansi_header", "interface_ansi_header"},
            {"interface_identifier"},
        )
    if node_type == "program_declaration":
        name = _name_from_direct(node, source_bytes, {"program_identifier"})
        if name:
            return name
        return _name_from_child(
            node,
            source_bytes,
            {"program_nonansi_header", "program_ansi_header"},
            {"program_identifier"},
        )
    if node_type == "package_declaration":
        return _name_from_direct(node, source_bytes, {"package_identifier"})
    if node_type in {"class_declaration", "interface_class_declaration"}:
        return _name_from_direct(node, source_bytes, {"class_identifier"})
    if node_type == "checker_declaration":
        return _name_from_direct(node, source_bytes, {"checker_identifier"})
    if node_type == "config_declaration":
        return _name_from_direct(node, source_bytes, {"config_identifier"})
    if node_type == "function_declaration":
        return _name_from_child(
            node, source_bytes, {"function_body_declaration"}, {"function_identifier"}
        )
    if node_type == "task_declaration":
        return _name_from_child(
            node, source_bytes, {"task_body_declaration"}, {"task_identifier"}
        )
    if node_type == "function_prototype":
        return _name_from_direct(node, source_bytes, {"function_identifier"})
    if node_type == "task_prototype":
        return _name_from_direct(node, source_bytes, {"task_identifier"})
    if node_type in {"class_constructor_declaration", "class_constructor_prototype"}:
        return "new"
    return None


def _find_enclosing_container(node, container_by_id):
    parent = node.parent
    while parent is not None:
        node_key = _node_key(parent)
        if node_key in container_by_id:
            return container_by_id[node_key]
        parent = parent.parent
    return None


def checkout_commit(repo_path, commit_id):
    """Checkout the specified commit in the given local git repository.
    :param repo_path: Path to the local git repository
    :param commit_id: Commit ID to checkout
    :return: None
    """
    try:
        # Change directory to the provided repository path and checkout the specified commit
        print(f"Checking out commit {commit_id} in repository at {repo_path}...")
        subprocess.run(["git", "-C", repo_path, "checkout", commit_id], check=True)
        print("Commit checked out successfully.")
    except subprocess.CalledProcessError as e:
        print(f"An error occurred while running git command: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")


def clone_repo(repo_name, repo_playground):
    try:

        print(
            f"Cloning repository from https://github.com/{repo_name}.git to {repo_playground}/{repo_to_top_folder[repo_name]}..."
        )
        subprocess.run(
            [
                "git",
                "clone",
                f"https://github.com/{repo_name}.git",
                f"{repo_playground}/{repo_to_top_folder[repo_name]}",
            ],
            check=True,
        )
        print("Repository cloned successfully.")
    except subprocess.CalledProcessError as e:
        print(f"An error occurred while running git command: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")


def get_project_structure_from_scratch(
    repo_name, commit_id, instance_id, repo_playground
):

    # Generate a temperary folder and add uuid to avoid collision
    repo_playground = os.path.join(repo_playground, str(uuid.uuid4()))

    # assert playground doesn't exist
    assert not os.path.exists(repo_playground), f"{repo_playground} already exists"

    # create playground
    os.makedirs(repo_playground)

    #clone_repo(repo_name, repo_playground)
    #checkout_commit(f"{repo_playground}/{repo_to_top_folder[repo_name]}", commit_id)
    #structure = create_structure(f"{repo_playground}/{repo_to_top_folder[repo_name]}")
    structure = create_structure(f"{repo_name}")
    # clean up
    #subprocess.run(
    #    ["rm", "-rf", f"{repo_playground}/{repo_to_top_folder[repo_name]}"], check=True
    #)
    d = {
        "repo": repo_name,
        "base_commit": commit_id,
        "structure": structure,
        "instance_id": instance_id,
    }
    return d


def parse_verilog_file(file_path, file_content=None):
    """Parse a Verilog/SystemVerilog file with tree-sitter."""
    if file_content is None:
        try:
            with open(file_path, "r") as file:
                file_content = file.read()
        except Exception as e:  # Catch all types of exceptions
            print(f"Error in file {file_path}: {e}")
            return [], [], ""

    parser = _get_verilog_parser()
    source_bytes = file_content.encode("utf-8", errors="replace")
    tree = parser.parse(source_bytes)

    class_info = []
    function_names = []
    container_by_id = {}
    lines = file_content.splitlines()

    for node in _iter_tree(tree.root_node):
        if node.type not in _MODULE_NODE_TYPES:
            continue

        container_name = _node_name(node, source_bytes)
        if not container_name:
            continue
        start_line = node.start_point[0] + 1
        end_line = node.end_point[0] + 1

        container_info = {
            "name": container_name,
            "start_line": start_line,
            "end_line": end_line,
            "text": lines[start_line - 1 : end_line],
            "methods": [],
        }
        class_info.append(container_info)
        container_by_id[_node_key(node)] = container_info

    for node in _iter_tree(tree.root_node):
        if node.type not in _FUNC_NODE_TYPES:
            continue
        func_name = _node_name(node, source_bytes)
        if not func_name:
            continue
        start_line = node.start_point[0] + 1
        end_line = node.end_point[0] + 1
        func_info = {
            "name": func_name,
            "start_line": start_line,
            "end_line": end_line,
            "text": lines[start_line - 1 : end_line],
        }
        container_info = _find_enclosing_container(node, container_by_id)
        if container_info is None:
            function_names.append(func_info)
        else:
            container_info["methods"].append(func_info)

    return class_info, function_names, lines


def parse_python_file(file_path, file_content=None):
    """Compatibility shim: parses Verilog/SystemVerilog files."""
    return parse_verilog_file(file_path, file_content)


def create_structure(directory_path):
    """Create the structure of the repository directory by parsing Verilog files."""
    structure = {}

    for root, _, files in os.walk(directory_path):
        repo_name = os.path.basename(directory_path)
        relative_root = os.path.relpath(root, directory_path)
        if relative_root == ".":
            relative_root = repo_name
        curr_struct = structure
        for part in relative_root.split(os.sep):
            if part not in curr_struct:
                curr_struct[part] = {}
            curr_struct = curr_struct[part]
        for file_name in files:
            _, ext = os.path.splitext(file_name)
            if ext.lower() in _VERILOG_EXTENSIONS:
                file_path = os.path.join(root, file_name)
                class_info, function_names, file_lines = parse_verilog_file(file_path)
                curr_struct[file_name] = {
                    "classes": class_info,
                    "functions": function_names,
                    "text": file_lines,
                }
            else:
                curr_struct[file_name] = {}

    return structure
