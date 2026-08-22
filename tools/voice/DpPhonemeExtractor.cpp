#include <windows.h>

#include <iostream>
#include <sstream>
#include <string>

struct ILipSyncPhonemeRecognizer
{
    struct SPhoneme
    {
        enum { MAX_PHONEME_LENGTH = 8 };

        int startTime;
        int endTime;
        int nPhonemeCode;
        char sPhoneme[MAX_PHONEME_LENGTH];
        float intensity;
    };

    struct SWord
    {
        int startTime;
        int endTime;
        char* sWord;
    };

    struct SSentence
    {
        char* sSentence;
        int nWordCount;
        SWord* pWords;
        int nPhonemeCount;
        SPhoneme* pPhonemes;
    };

    virtual void Release() = 0;
    virtual bool RecognizePhonemes(
        const char* wavFile,
        const char* text,
        SSentence** output
    ) = 0;
    virtual const char* GetLastError() = 0;
};

using CreatePhonemeParser = ILipSyncPhonemeRecognizer* (*)();

static std::string ToAnsi(const wchar_t* value)
{
    const int size = WideCharToMultiByte(
        CP_ACP,
        0,
        value,
        -1,
        nullptr,
        0,
        nullptr,
        nullptr
    );
    if (size <= 0)
    {
        return {};
    }

    std::string result(static_cast<size_t>(size - 1), '\0');
    WideCharToMultiByte(
        CP_ACP,
        0,
        value,
        -1,
        result.data(),
        size,
        nullptr,
        nullptr
    );
    return result;
}

static std::string JsonEscape(const char* value)
{
    std::ostringstream output;
    if (value == nullptr)
    {
        return {};
    }

    for (const unsigned char character : std::string(value))
    {
        switch (character)
        {
        case '\\': output << "\\\\"; break;
        case '"': output << "\\\""; break;
        case '\b': output << "\\b"; break;
        case '\f': output << "\\f"; break;
        case '\n': output << "\\n"; break;
        case '\r': output << "\\r"; break;
        case '\t': output << "\\t"; break;
        default:
            if (character < 0x20)
            {
                output << "\\u00";
                const char* digits = "0123456789abcdef";
                output << digits[(character >> 4) & 0x0f];
                output << digits[character & 0x0f];
            }
            else
            {
                output << character;
            }
        }
    }
    return output.str();
}

int wmain(int argc, wchar_t** argv)
{
    if (argc != 4)
    {
        std::cerr << "usage: dp-phonemes.exe <plugin-root> <wave> <text>\n";
        return 2;
    }

    const std::wstring pluginRoot = argv[1];
    const std::wstring pluginPath = pluginRoot + L"\\LipSync_Annosoft.dll";
    const std::string wavePath = ToAnsi(argv[2]);
    const std::string text = ToAnsi(argv[3]);

    const DWORD previousDirectorySize = GetCurrentDirectoryW(0, nullptr);
    std::wstring previousDirectory(previousDirectorySize, L'\0');
    GetCurrentDirectoryW(previousDirectorySize, previousDirectory.data());
    previousDirectory.resize(previousDirectorySize - 1);

    SetDllDirectoryW(pluginRoot.c_str());
    if (!SetCurrentDirectoryW(pluginRoot.c_str()))
    {
        std::cerr << "failed to enter plugin directory: " << GetLastError() << "\n";
        return 3;
    }

    HMODULE library = LoadLibraryW(pluginPath.c_str());
    if (library == nullptr)
    {
        std::cerr << "failed to load LipSync_Annosoft.dll: " << GetLastError() << "\n";
        SetCurrentDirectoryW(previousDirectory.c_str());
        return 4;
    }

    auto create = reinterpret_cast<CreatePhonemeParser>(
        GetProcAddress(library, "CreatePhonemeParser")
    );
    if (create == nullptr)
    {
        std::cerr << "CreatePhonemeParser export is missing\n";
        FreeLibrary(library);
        SetCurrentDirectoryW(previousDirectory.c_str());
        return 5;
    }

    ILipSyncPhonemeRecognizer* recognizer = create();
    ILipSyncPhonemeRecognizer::SSentence* sentence = nullptr;
    const bool recognized = recognizer != nullptr && recognizer->RecognizePhonemes(
        wavePath.c_str(),
        text.c_str(),
        &sentence
    );
    if (!recognized || sentence == nullptr)
    {
        const char* error = recognizer == nullptr
            ? "CreatePhonemeParser returned null"
            : recognizer->GetLastError();
        std::cerr << "phoneme recognition failed: "
                  << (error == nullptr ? "unknown error" : error)
                  << "\n";
        if (recognizer != nullptr)
        {
            recognizer->Release();
        }
        FreeLibrary(library);
        SetCurrentDirectoryW(previousDirectory.c_str());
        return 6;
    }

    std::cout << "{\"text\":\"" << JsonEscape(text.c_str()) << "\",\"words\":[";
    for (int index = 0; index < sentence->nWordCount; ++index)
    {
        if (index > 0)
        {
            std::cout << ',';
        }
        const auto& word = sentence->pWords[index];
        std::cout << "{\"word\":\"" << JsonEscape(word.sWord)
                  << "\",\"startMs\":" << word.startTime
                  << ",\"endMs\":" << word.endTime << '}';
    }
    std::cout << "],\"phonemes\":[";
    for (int index = 0; index < sentence->nPhonemeCount; ++index)
    {
        if (index > 0)
        {
            std::cout << ',';
        }
        const auto& phoneme = sentence->pPhonemes[index];
        std::cout << "{\"phoneme\":\"" << JsonEscape(phoneme.sPhoneme)
                  << "\",\"code\":" << phoneme.nPhonemeCode
                  << ",\"startMs\":" << phoneme.startTime
                  << ",\"endMs\":" << phoneme.endTime
                  << ",\"intensity\":" << phoneme.intensity << '}';
    }
    std::cout << "]}";

    recognizer->Release();
    FreeLibrary(library);
    SetCurrentDirectoryW(previousDirectory.c_str());
    return 0;
}
