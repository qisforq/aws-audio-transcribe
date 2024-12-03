#!/bin/bash

check_dependencies() {
    echo "Checking dependencies..."
    
    # Check if Python3 is installed
    if ! command -v python3 &> /dev/null; then
        echo "Error: Python 3 is required but not installed."
        echo "Please install Python 3 using: brew install python3"
        exit 1
    fi

    # Check if pip3 is installed
    if ! command -v pip3 &> /dev/null; then
        echo "Error: pip3 is required but not installed."
        echo "Please install pip3 and try again."
        exit 1
    fi

    # Check if virtual environment exists, create if it doesn't
    VENV_DIR="$HOME/.athletifi_transcribe_venv"
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating virtual environment for AthletiFi Transcriber..."
        python3 -m venv "$VENV_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create virtual environment."
            exit 1
        fi
    fi

    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to activate virtual environment."
        exit 1
    fi

    # Check if boto3 is installed in virtual environment, install if missing
    if ! python3 -c "import boto3" &> /dev/null; then
        echo "boto3 package not found. Installing in virtual environment..."
        if pip3 install boto3; then
            echo "Successfully installed boto3"
        else
            echo "Error: Failed to install boto3. Please try manually using:"
            echo "source $VENV_DIR/bin/activate && pip3 install boto3"
            deactivate
            exit 1
        fi
    fi

    # Check if requests is installed in virtual environment, install if missing
    if ! python3 -c "import requests" &> /dev/null; then
        echo "requests package not found. Installing in virtual environment..."
        if pip3 install requests; then
            echo "Successfully installed requests"
        else
            echo "Error: Failed to install requests. Please try manually using:"
            echo "source $VENV_DIR/bin/activate && pip3 install requests"
            deactivate
            exit 1
        fi
    fi

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI is required but not installed."
        echo "Please install AWS CLI using: brew install awscli"
        echo "Then configure it with: aws configure"
        deactivate
        exit 1
    fi
}

cleanup() {
    # Deactivate virtual environment if it's active
    if [ -n "$VIRTUAL_ENV" ]; then
        deactivate
    fi
}

# Set up trap to ensure virtual environment is deactivated on exit
trap cleanup EXIT

print_welcome_message() {
    cat << "EOF"
    ╔════════════════════════════════════════════════════════════════════════════╗
    ║                 Welcome to AthletiFi Audio Transcriber                     ║
    ╚════════════════════════════════════════════════════════════════════════════╝

    This script helps you work with AWS Transcribe, supporting multiple audio 
    formats and automatic speaker detection.

    ┌──────────────────────────────────────────┐
    │           Before You Begin:              │
    └──────────────────────────────────────────┘
    1. Ensure you have AWS CLI configured with appropriate permissions
    2. Python 3 with boto3 package installed
    3. Access to required input files/S3 paths
    
    Supported audio formats:
    ✦ MP3 (.mp3)         ✦ WAV (.wav)
    ✦ M4A (.m4a)         ✦ FLAC (.flac)
    ✦ MP4 (.mp4)         ✦ OGG (.ogg)
    ✦ WebM (.webm)

EOF
    print_menu
}

print_menu() {
    cat << "EOF"

    ┌──────────────────────────────────────────┐
    │           Available Options:             │
    └──────────────────────────────────────────┘
    1. Create new transcription job from S3 audio file
    2. Convert local JSON transcript file
    3. Convert transcript using job name
    4. Exit

    Please enter your choice (1-4): 
EOF
}

create_transcription_job() {
    echo "Starting new transcription job..."
    
    # Prompt for S3 path
    read -p "Enter S3 path (e.g., s3://bucket-name/path/): " S3_PATH
    
    # Remove trailing slash if present
    S3_PATH=${S3_PATH%/}

    # Validate S3 path format
    if [[ ! $S3_PATH =~ ^s3://[^/]+(/[^/]+)*$ ]]; then
        echo "Error: Invalid S3 path format. Must start with 's3://'"
        return 1
    fi

    # Extract bucket and prefix using parameter expansion
    BUCKET=${S3_PATH#s3://}
    BUCKET=${BUCKET%%/*}
    PREFIX=${S3_PATH#s3://$BUCKET/}
    if [ "$PREFIX" = "$S3_PATH" ]; then
        PREFIX=""
    fi

    echo "Searching for audio files in: $S3_PATH"

    # Get list of files first
    files=$(aws s3 ls "$S3_PATH/" | awk '/\.(m4a|mp3|mp4|wav|flac|ogg|webm)$/ {$1=""; $2=""; $3=""; print substr($0,4)}')

    if [ -z "$files" ]; then
        echo "No audio files found in the specified S3 path."
        return 1
    fi

    # Process each file
    echo "$files" | while IFS= read -r filename; do
        # Trim leading/trailing whitespace
        filename=$(echo "$filename" | xargs)
        
        # Skip if empty
        [ -z "$filename" ] && continue
        
        # Create job name by replacing spaces and special chars with hyphens
        job_name=$(echo "$filename" | tr -cs '[:alnum:]' '-' | sed 's/-*$//;s/^-*//' | sed 's/\.[^.]*$//')
        
        echo "----------------------------------------"
        echo "File: $filename"
        echo "Job name will be: $job_name"
        
        # Prompt for number of speakers
        while true; do
            read -p "Enter number of speakers (2-30), '0' or 'skip' to skip this file: " speaker_count </dev/tty
            if [ "$speaker_count" = "skip" ] || [ "$speaker_count" = "0" ]; then
                echo "Skipping $filename"
                continue 2
            elif [[ "$speaker_count" =~ ^[0-9]+$ ]] && [ "$speaker_count" -ge 2 ] && [ "$speaker_count" -le 30 ]; then
                break
            else
                echo "Please enter a valid number between 2 and 30, '0' or 'skip'"
            fi
        done
        
        echo "Starting transcription job with $speaker_count speakers..."
        
        aws transcribe start-transcription-job \
            --transcription-job-name "$job_name" \
            --language-code "en-US" \
            --media-format "${filename##*.}" \
            --media "MediaFileUri=s3://${BUCKET}/${PREFIX:+$PREFIX/}${filename}" \
            --settings "{
                \"ShowSpeakerLabels\": true,
                \"MaxSpeakerLabels\": $speaker_count,
                \"ChannelIdentification\": true
            }"
        
        if [ $? -eq 0 ]; then
            echo "Successfully started transcription job for $filename"
            echo "You can process this job later using option 3 from the main menu."
        else
            echo "Failed to start transcription job for $filename"
            echo "Please check your AWS credentials and permissions"
        fi
        
        # Add a small delay to avoid hitting API rate limits
        sleep 2
    done

    echo "All files processed. Returning to main menu..."
}

print_completion_message() {
    cat << "EOF"

    Thank you for using the AthletiFi Audio Transcriber!
    
    ┌──────────────────────────────────────────┐
    │            Process Complete!             │
    └──────────────────────────────────────────┘
    
    Returning to main menu...
EOF
}

# Main program loop
check_dependencies
print_welcome_message

while true; do
    read choice
    
    case $choice in
        1)
            create_transcription_job
            print_menu
            ;;
        2)
            echo "Converting local JSON transcript file..."
            python3 convert-aws-transcript.py
            print_completion_message
            print_menu
            ;;
        3)
            echo "Converting transcript using job name..."
            python3 convert-aws-transcript-by-jobname.py
            print_completion_message
            print_menu
            ;;
        4)
            echo "Thank you for using AthletiFi Audio Transcriber. Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, 3, or 4."
            print_menu
            ;;
    esac
done