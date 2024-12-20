import json
import sys
import os
import re

def print_welcome_message():
    welcome_text = """
    ╔════════════════════════════════════════════════════════════════════╗
    ║                  Welcome to AWS Transcript Converter                ║
    ╚════════════════════════════════════════════════════════════════════╝

    This script converts AWS Transcribe JSON output into a readable format.
    It will help you:

    1. Process speaker-separated transcripts
    2. Name your speakers for better readability
    3. Save the result in a clean text format

    Please ensure you have your AWS Transcribe JSON file ready.
    Let's get started!
    """
    print(welcome_text)

def sanitize_path(input_path):
    """
    Sanitize and validate the input file path.
    Handles both escaped paths and quoted paths.
    
    Args:
        input_path (str): Raw input path
        
    Returns:
        str: Sanitized path if valid
        
    Raises:
        FileNotFoundError: If path is invalid or file doesn't exist
    """
    # First, strip any whitespace and quotes
    path = input_path.strip().strip("'\"")
    
    # Handle doubled backslashes that can occur from shell input
    path = path.replace("\\\\", "\\")
    
    # Create variations of the path to try
    paths_to_try = [
        path,  # Original path
        path.replace("\\ ", " ").replace("\\(", "(").replace("\\)", ")"),  # Unescape spaces and parentheses
        re.sub(r'\\(.)', r'\1', path),  # Unescape all special characters
    ]
    
    # Try each path variation
    paths_tried = set()
    for p in paths_to_try:
        p = p.strip()
        if p in paths_tried:
            continue
            
        paths_tried.add(p)
        if os.path.exists(p):
            return p
    
    raise FileNotFoundError(
        f"Could not find the file. You can specify the path either:\n"
        f"1. With escaped special characters: /path/to/my\\ file\\(1\\).json\n"
        f"2. In quotes: '/path/to/my file (1).json'"
    )

def get_valid_file_path():
    """
    Repeatedly prompt for a valid file path until one is provided.
    
    Returns:
        str: Valid, sanitized file path
    """
    print("\n┌─ File Input ───────────────────────────────────────────────────┐")
    print("│ You can enter the path either:                                  │")
    print("│ • With escaped spaces: /path/to/my\\ file\\(1\\).json            │")
    print("│ • In quotes: '/path/to/my file (1).json'                       │")
    print("└────────────────────────────────────────────────────────────────┘")
    
    while True:
        try:
            file_path = input("\nPlease enter the path to your AWS Transcribe JSON file: ")
            return sanitize_path(file_path)
        except FileNotFoundError as e:
            print(f"\nError: {e}")
            continue
        except Exception as e:
            print(f"\nUnexpected error: {str(e)}")
            raise

def process_transcript(json_file_path, speaker_names=None):
    """
    Process AWS Transcribe JSON output into a readable transcript with speaker labels.
    
    Args:
        json_file_path (str): Path to the JSON file
        speaker_names (dict): Dictionary mapping speaker labels to names (e.g., {'spk_0': 'John'})
    
    Returns:
        str: Formatted transcript
    """
    # Read and parse JSON file
    with open(json_file_path, 'r') as file:
        data = json.load(file)
    
    # If no speaker names provided, prompt for them
    if speaker_names is None:
        speaker_names = {}
        num_speakers = data['results']['speaker_labels']['speakers']
        print(f"\n┌─ Speaker Names ─────────────────────────────────────────────────┐")
        print(f"│ Detected {num_speakers} speakers in the transcript.                    │")
        print(f"│ Please provide names for each speaker for better readability.    │")
        print(f"└────────────────────────────────────────────────────────────────┘")
        
        for i in range(num_speakers):
            speaker_label = f"spk_{i}"
            while True:
                name = input(f"\nPlease enter a name for speaker {i+1} (currently labeled as {speaker_label}): ").strip()
                if name:  # Ensure name isn't empty
                    break
                print("Name cannot be empty. Please try again.")
            speaker_names[speaker_label] = name
    
    # Process segments
    transcript_parts = []
    current_speaker = None
    current_text = []
    
    for segment in data['results']['audio_segments']:
        speaker = segment['speaker_label']
        
        # If we're switching to a new speaker, add the previous segment
        if current_speaker is not None and current_speaker != speaker:
            speaker_name = speaker_names.get(current_speaker, current_speaker)
            transcript_parts.append(f"\n{speaker_name}: {' '.join(current_text)}")
            current_text = []
        
        current_speaker = speaker
        current_text.append(segment['transcript'])
    
    # Add the last segment
    if current_text:
        speaker_name = speaker_names.get(current_speaker, current_speaker)
        transcript_parts.append(f"\n{speaker_name}: {' '.join(current_text)}")
    
    # Join all parts and format
    final_transcript = ''.join(transcript_parts).strip()
    
    return final_transcript, speaker_names

def print_concluding_message(output_file):
    concluding_message = f"""
    ╔════════════════════════════════════════════════════════════════════╗
    ║              AWS Transcript Converter - Process Complete!           ║
    ╚════════════════════════════════════════════════════════════════════╝

    ┌──────────────────────────────────────────────────────────────────┐
    │ Your transcript has been successfully processed and saved to:     │
    │ {output_file}
    └──────────────────────────────────────────────────────────────────┘

    Thank you for using the AWS Transcript Converter!
    """
    print(concluding_message)

def main():
    print_welcome_message()
    
    try:
        # Get valid file path from user
        json_file = get_valid_file_path()
        
        # Process the transcript
        transcript, speakers = process_transcript(json_file)
        
        print("\nProcessed Transcript:")
        print("=" * 50)
        print(transcript)
        print("=" * 50)
        
        # Save the transcript to a file
        output_dir = os.path.dirname(json_file)
        base_name = os.path.splitext(os.path.basename(json_file))[0]
        output_file = os.path.join(output_dir, f"{base_name}_processed.txt")
        
        with open(output_file, 'w') as f:
            f.write(transcript)
        
        print_concluding_message(output_file)
        
    except Exception as e:
        print(f"\nError processing transcript: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()