// samtool: SAM, exactly as the game speaks it, for the VoxHack Editor.
//
// Built by tools/deploy.sh (build/sam/samtool.exe) from the engine's own
// SAM code (external/luanti/lib/sam, src/client/sound/sam_unity.c and
// sam_speech.cpp), so a preview sounds like the game.
//
//   samtool [--speed N] [--pitch N] [--throat N] [--mouth N] [--sing]
//           [--phonetic] [--smooth] [--no-tone] [--dict FILE] [--fx CHAIN]
//           (--wav OUT.wav | --phonemes)    < text (UTF-8)
//
// --wav writes 16-bit mono at 22050 Hz; --phonemes prints the phonemes SAM
// reads, one piece per line. Exit status 1 if there was nothing to say.

#include "sam_speech.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

static void put32(std::ofstream &f, unsigned v) { f.write((const char *)&v, 4); }
static void put16(std::ofstream &f, unsigned short v) { f.write((const char *)&v, 2); }

int main(int argc, char **argv)
{
	nhvsam::Settings s;
	std::string dict_path, wav;
	bool phonemes = false;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto num = [&](int &v) { if (i + 1 < argc) v = std::atoi(argv[++i]); };
		if (a == "--speed") num(s.speed);
		else if (a == "--pitch") num(s.pitch);
		else if (a == "--throat") num(s.throat);
		else if (a == "--mouth") num(s.mouth);
		else if (a == "--sing") s.sing = true;
		else if (a == "--phonetic") s.phonetic = true;
		else if (a == "--smooth") s.smooth = true;
		else if (a == "--no-tone") s.tone = false;
		else if (a == "--dict" && i + 1 < argc) dict_path = argv[++i];
		else if (a == "--fx" && i + 1 < argc) s.effects = argv[++i];
		else if (a == "--wav" && i + 1 < argc) wav = argv[++i];
		else if (a == "--phonemes") phonemes = true;
		else {
			std::cerr << "samtool: unknown option " << a << std::endl;
			return 2;
		}
	}
	std::ostringstream in;
	in << std::cin.rdbuf();
	std::string text = in.str();

	nhvsam::Dictionary dict;
	if (!dict_path.empty()) {
		std::ifstream f(dict_path, std::ios::binary);
		std::ostringstream ss;
		ss << f.rdbuf();
		dict = nhvsam::parseDictionary(ss.str());
	}

	if (phonemes) {
		auto list = nhvsam::toPhonemes(text, s, &dict);
		for (const std::string &p : list)
			std::cout << p << "\n";
		return list.empty() ? 1 : 0;
	}
	std::vector<short> pcm = nhvsam::speak(text, s, &dict);
	if (pcm.empty())
		return 1;
	std::ofstream f(wav, std::ios::binary);
	unsigned bytes = (unsigned)(pcm.size() * 2);
	f.write("RIFF", 4); put32(f, 36 + bytes); f.write("WAVEfmt ", 8);
	put32(f, 16); put16(f, 1); put16(f, 1); put32(f, nhvsam::RATE); put32(f, nhvsam::RATE * 2);
	put16(f, 2); put16(f, 16);
	f.write("data", 4); put32(f, bytes);
	f.write((const char *)pcm.data(), bytes);
	return f ? 0 : 1;
}
