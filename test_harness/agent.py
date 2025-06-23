"""Agent definition that generates a testbench."""

import constants

from vertexai.preview.generative_models import GenerativeModel
import vertexai
import subprocess
import tempfile
import pathlib
#vertexai.init(location="us-central1")
#model = GenerativeModel("gemini-2.0-flash-001")
#response = model.generate_content("Say hi from inside the ICLAD Hackathon container!")
#print(response.candidates[0].text)

def extract_header(model, mutant0):
    prompt = f"""You are an expert in digital hardware design. Given the following module, please return the module header.
    {mutant0}

    Only return the module header with the bit widths of the inputs and outputs, and don't provide any additional information.
    """
    header = model.generate_content(prompt)
    header_return = '\n'.join(header.candidates[0].text.splitlines()[1:-1])
    print(header_return)
    return header_return

def finding_bugs(model, functional_desc):
    prompt = f"""
    You are an expert in digital hardware verification. Given the following functional description of a module:
    {functional_desc}
    Your task is to identify and describe possible bugs that may exist in implementations of this module.
    Provide a thorough, specific, and concise list of bullet points of potential bugs. Focus on realistic design, logic, or 
    timing issues. Avoid unnecessary commentary or speculation beyond what's relevant to potential bugs.
    """
    potential_bugs = model.generate_content(prompt)
    return potential_bugs

def creating_tb(model, functional_desc, potential_bugs, module_header):
    new_prompt = f"""
    You are an expert in digital hardware verification. 
    You are given the functional description of a Verilog module: 
    {functional_desc}
    Your task is to generate a comprehensive and concise Verilog testbench that verifies the correctness of a module 
    implementing this description. The testbench should aim to detect common issues, cover edge cases, 
    and validate core functionality.
    Additionally, consider the following potential bugs that may exist in the implementation: 
    {potential_bugs.candidates[0].text}
    Use this list to inform what tests to include in the testbench. 

    The testbench should adhere to the following requirements:
    Your output should be only the Verilog testbench code, with no extra explanation or commentary. 
    Do not write any additional modules other than the testbench module. 
    The testbench module name is tb. 
    This is the module header of the {module_header}
    It outputs $display("TESTS PASSED") if the Verilog module passes the testbench. 
    It calls an error if the Verilog module does not pass the testbench.
    It calls $finish in the end.
    """
    testbench_output = model.generate_content(new_prompt)
    to_return = '\n'.join(testbench_output.candidates[0].text.splitlines()[1:-1])
    return to_return

# def fixing_syntax(model, testbench):
#     prompt = f"""
#     Given the following testbench module written in Verilog code: {testbench}
#     identify and correct the syntax errors. These errors may possibly concern bit arithmetic,
#     logical formulas, or Verilog syntax rules. 
#     """
    
def check_verilog_syntax(verilog_code, mutant0, top_module="tb"):
    with tempfile.TemporaryDirectory() as tmpdir:
        tb_path = pathlib.Path(tmpdir) / "temp_tb.v"
        tb_path.write_text(verilog_code)

        mutant_path = pathlib.Path(tmpdir) / "mutant0.v"
        mutant_path.write_text(mutant0)

        output_path = pathlib.Path(tmpdir) / "a.out"

        try:
            subprocess.run(
            # iverilog -g2012 -o /tmp/tmpf2ynufpd/out -s tb /workspace/iclad_hackathon/ICLAD-Hackathon-2025/problem-categories/Google-Verification-ICLAD25-Hackathon/visible_problems/fifo_flops/tb.v /workspace/iclad_hackathon/ICLAD-Hackathon-2025/problem-categories/Google-Verification-ICLAD25-Hackathon/visible_problems/fifo_flops/mutant_0.v
                ["iverilog", "-g2012", "-o", str(output_path), "-s", top_module, str(tb_path), str(mutant_path)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            ) 
            print("Syntax is valid.")
            return True, ""
        except subprocess.CalledProcessError as e:
            print("Syntax error detected:")
            print(e.stderr.decode())
            return False, e.stderr.decode()

def fix_verilog_syntax(model, verilog_code, error_message, module_header):
    prompt = f"""
    Given the following testbench module written in Verilog code: {verilog_code}
    as well as the following error message for syntax {error_message}, please rewrite the code such that
    there are no syntax issues.
    As before, the testbench should adhere to the following requirements:
    Your output should be only the Verilog testbench code, with no extra explanation or commentary. 
    Do not write any additional modules other than the testbench module. 
    The testbench module name is tb. 
    This is the module header of the {module_header}
    It outputs $display("TESTS PASSED") if the Verilog module passes the testbench. 
    It calls an error if the Verilog module does not pass the testbench.
    It calls $finish in the end.
    """
    fixed_code = model.generate_content(prompt)
    
    to_return = '\n'.join(fixed_code.candidates[0].text.splitlines()[1:-1])
    
    return to_return


# TODO: Implement this.
def generate_testbench(file_name_to_content: dict[str, str]) -> str:
    # MODEL #
    vertexai.init(location="us-central1")
    model = GenerativeModel("gemini-2.5-pro")
    # PROMPTING #
    functional_desc = file_name_to_content['specification.md'] 
    potential_bugs = finding_bugs(model, functional_desc)
    # module_header = file_name_to_content["mutant_0.v"].splitlines()[0]
    module_header = extract_header(model, file_name_to_content["mutant_0.v"])
    to_return = creating_tb(model, functional_desc, potential_bugs, module_header)
    print(to_return)
    isGood = False
    while not isGood:
        isGood, error = check_verilog_syntax(to_return, file_name_to_content["mutant_0.v"], "tb")
        if not isGood:
            to_return = fix_verilog_syntax(model, to_return, error, module_header)
    # return testbench_output.candidates[0].text
    return to_return
