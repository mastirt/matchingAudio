import streamlit as st
import librosa
import numpy as np
import io

def extract_mfcc(audio_data):
    y, sr = librosa.load(io.BytesIO(audio_data), sr=None)
    mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
    return mfccs.tolist()

st.title('MFCC Extraction App')

st.write("Upload an audio file to extract MFCC features:")

uploaded_file = st.file_uploader("Choose an audio file", type=["wav", "mp3", "flac"])

if uploaded_file is not None:
    try:
        audio_data = uploaded_file.read()
        mfccs = extract_mfcc(audio_data)
        st.write("MFCCs extracted successfully!")
        st.json(mfccs)
    except Exception as e:
        st.error(f"An error occurred: {e}")