param(
    [Parameter(Mandatory)][string]$BaseImage,
    [Parameter(Mandatory)][string]$ExtensionImage,
    [Parameter(Mandatory)][string]$OutputImage
)

$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace DarkPassenger.Tools
{
    public static class DpFacialImageMerger
    {
        private const uint SupportedFileVersion = 0x746;
        private const ushort SupportedChunkType = 0x3007;
        private const ushort SupportedChunkVersion = 0x0971;
        private const uint HeaderSize = 16;
        private const uint TableEntrySize = 16;

        private sealed class Chunk
        {
            public ushort Type;
            public ushort Version;
            public uint Id;
            public uint Size;
            public uint SourceOffset;
            public uint OutputOffset;
            public string AnimationPath = string.Empty;
        }

        private sealed class Image
        {
            public string Path = string.Empty;
            public List<Chunk> Chunks = new List<Chunk>();
        }

        public static string Merge(
            string baseImagePath,
            string extensionImagePath,
            string outputImagePath)
        {
            string baseFullPath = Path.GetFullPath(baseImagePath);
            string extensionFullPath = Path.GetFullPath(extensionImagePath);
            string outputFullPath = Path.GetFullPath(outputImagePath);

            if (String.Equals(baseFullPath, extensionFullPath,
                    StringComparison.OrdinalIgnoreCase) ||
                String.Equals(baseFullPath, outputFullPath,
                    StringComparison.OrdinalIgnoreCase) ||
                String.Equals(extensionFullPath, outputFullPath,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "Base, extension, and output facial images must be different files.");
            }

            Image baseImage = ReadImage(baseFullPath);
            Image extensionImage = ReadImage(extensionFullPath);
            if (extensionImage.Chunks.Count == 0)
            {
                throw new InvalidDataException(
                    "The extension facial image contains no animation chunks.");
            }

            var knownPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            uint maximumId = 0;
            foreach (Chunk chunk in baseImage.Chunks)
            {
                if (!knownPaths.Add(chunk.AnimationPath))
                {
                    throw new InvalidDataException(
                        "The base facial image contains duplicate animation path: " +
                        chunk.AnimationPath);
                }
                if (chunk.Id > maximumId)
                {
                    maximumId = chunk.Id;
                }
            }

            foreach (Chunk chunk in extensionImage.Chunks)
            {
                if (!knownPaths.Add(chunk.AnimationPath))
                {
                    throw new InvalidDataException(
                        "The extension facial animation already exists in the base image: " +
                        chunk.AnimationPath);
                }
                if (maximumId == UInt32.MaxValue)
                {
                    throw new InvalidDataException(
                        "No free facial animation chunk IDs remain.");
                }
                chunk.Id = ++maximumId;
            }

            long totalCountLong =
                (long)baseImage.Chunks.Count + extensionImage.Chunks.Count;
            if (totalCountLong > UInt32.MaxValue)
            {
                throw new InvalidDataException(
                    "Merged facial image exceeds the supported chunk count.");
            }
            uint totalCount = (uint)totalCountLong;
            ulong dataOffset = Align4(
                (ulong)HeaderSize + ((ulong)totalCount * TableEntrySize));

            foreach (Chunk chunk in EnumerateChunks(baseImage, extensionImage))
            {
                if (dataOffset > UInt32.MaxValue)
                {
                    throw new InvalidDataException(
                        "Merged facial image exceeds the 32-bit offset range.");
                }
                chunk.OutputOffset = (uint)dataOffset;
                dataOffset = Align4(dataOffset + chunk.Size);
            }
            if (dataOffset > UInt32.MaxValue)
            {
                throw new InvalidDataException(
                    "Merged facial image exceeds the supported file size.");
            }

            string outputDirectory = Path.GetDirectoryName(outputFullPath);
            if (String.IsNullOrEmpty(outputDirectory))
            {
                throw new InvalidOperationException(
                    "The output facial image must have a parent directory.");
            }
            Directory.CreateDirectory(outputDirectory);
            string temporaryPath = outputFullPath + "." +
                Guid.NewGuid().ToString("N") + ".tmp";

            try
            {
                using (var output = new FileStream(
                    temporaryPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None))
                using (var writer = new BinaryWriter(
                    output,
                    Encoding.ASCII,
                    leaveOpen: true))
                {
                    writer.Write(Encoding.ASCII.GetBytes("CrCh"));
                    writer.Write(SupportedFileVersion);
                    writer.Write(totalCount);
                    writer.Write(HeaderSize);

                    foreach (Chunk chunk in EnumerateChunks(
                        baseImage,
                        extensionImage))
                    {
                        writer.Write(chunk.Type);
                        writer.Write(chunk.Version);
                        writer.Write(chunk.Id);
                        writer.Write(chunk.Size);
                        writer.Write(chunk.OutputOffset);
                    }

                    WritePadding(output, Align4((ulong)output.Position));
                    CopyChunks(baseImage, output);
                    CopyChunks(extensionImage, output);
                    output.Flush(true);
                }

                File.Move(temporaryPath, outputFullPath, true);
            }
            catch
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
                throw;
            }

            return String.Format(
                "Merged {0} vanilla and {1} custom facial animations into {2}.",
                baseImage.Chunks.Count,
                extensionImage.Chunks.Count,
                outputFullPath);
        }

        private static Image ReadImage(string path)
        {
            if (!File.Exists(path))
            {
                throw new FileNotFoundException(
                    "Facial animation image was not found.",
                    path);
            }

            var image = new Image { Path = path };
            using (var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read))
            using (var reader = new BinaryReader(stream, Encoding.ASCII))
            {
                string signature = Encoding.ASCII.GetString(reader.ReadBytes(4));
                uint fileVersion = reader.ReadUInt32();
                uint chunkCount = reader.ReadUInt32();
                uint tableOffset = reader.ReadUInt32();
                if (signature != "CrCh" ||
                    fileVersion != SupportedFileVersion ||
                    tableOffset != HeaderSize)
                {
                    throw new InvalidDataException(String.Format(
                        "Unsupported facial image header in {0}: " +
                        "signature={1}, version=0x{2:X}, table={3}.",
                        path,
                        signature,
                        fileVersion,
                        tableOffset));
                }
                if (chunkCount > Int32.MaxValue)
                {
                    throw new InvalidDataException(
                        "Facial image has too many chunks to process: " + path);
                }

                for (int index = 0; index < (int)chunkCount; index++)
                {
                    stream.Position = tableOffset + ((long)index * TableEntrySize);
                    var chunk = new Chunk
                    {
                        Type = reader.ReadUInt16(),
                        Version = reader.ReadUInt16(),
                        Id = reader.ReadUInt32(),
                        Size = reader.ReadUInt32(),
                        SourceOffset = reader.ReadUInt32()
                    };
                    if (chunk.Type != SupportedChunkType ||
                        chunk.Version != SupportedChunkVersion)
                    {
                        throw new InvalidDataException(String.Format(
                            "Unsupported facial chunk in {0}: " +
                            "type=0x{1:X4}, version=0x{2:X4}.",
                            path,
                            chunk.Type,
                            chunk.Version));
                    }
                    if (chunk.Size < 5 ||
                        (ulong)chunk.SourceOffset + chunk.Size >
                        (ulong)stream.Length)
                    {
                        throw new InvalidDataException(
                            "Facial chunk points outside the image: " + path);
                    }
                    chunk.AnimationPath = ReadAnimationPath(
                        stream,
                        reader,
                        chunk);
                    if (String.IsNullOrWhiteSpace(chunk.AnimationPath))
                    {
                        throw new InvalidDataException(
                            "Facial chunk has an empty animation path: " + path);
                    }
                    image.Chunks.Add(chunk);
                }
            }
            return image;
        }

        private static string ReadAnimationPath(
            FileStream stream,
            BinaryReader reader,
            Chunk chunk)
        {
            stream.Position = chunk.SourceOffset + 4;
            int byteCount = (int)Math.Min(256u, chunk.Size - 4);
            byte[] bytes = reader.ReadBytes(byteCount);
            int terminator = Array.IndexOf(bytes, (byte)0);
            if (terminator < 0)
            {
                terminator = bytes.Length;
            }
            return Encoding.ASCII.GetString(bytes, 0, terminator);
        }

        private static IEnumerable<Chunk> EnumerateChunks(
            Image baseImage,
            Image extensionImage)
        {
            foreach (Chunk chunk in baseImage.Chunks)
            {
                yield return chunk;
            }
            foreach (Chunk chunk in extensionImage.Chunks)
            {
                yield return chunk;
            }
        }

        private static void CopyChunks(Image image, FileStream output)
        {
            using (var input = new FileStream(
                image.Path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read))
            {
                byte[] buffer = new byte[1024 * 1024];
                foreach (Chunk chunk in image.Chunks)
                {
                    if ((ulong)output.Position > chunk.OutputOffset)
                    {
                        throw new InvalidDataException(
                            "Merged facial chunk offsets overlap.");
                    }
                    WritePadding(output, chunk.OutputOffset);
                    input.Position = chunk.SourceOffset;
                    uint remaining = chunk.Size;
                    while (remaining > 0)
                    {
                        int requested = (int)Math.Min((uint)buffer.Length, remaining);
                        int read = input.Read(buffer, 0, requested);
                        if (read <= 0)
                        {
                            throw new EndOfStreamException(
                                "Unexpected end of facial image: " + image.Path);
                        }
                        output.Write(buffer, 0, read);
                        remaining -= (uint)read;
                    }
                }
            }
        }

        private static void WritePadding(FileStream output, ulong targetOffset)
        {
            if ((ulong)output.Position > targetOffset)
            {
                throw new InvalidDataException(
                    "Facial image writer advanced past the requested offset.");
            }
            byte[] zeros = new byte[4];
            while ((ulong)output.Position < targetOffset)
            {
                int count = (int)Math.Min(
                    (ulong)zeros.Length,
                    targetOffset - (ulong)output.Position);
                output.Write(zeros, 0, count);
            }
        }

        private static ulong Align4(ulong value)
        {
            return (value + 3UL) & ~3UL;
        }
    }
}
'@

if (-not ('DarkPassenger.Tools.DpFacialImageMerger' -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp
}

$message = [DarkPassenger.Tools.DpFacialImageMerger]::Merge(
    $BaseImage,
    $ExtensionImage,
    $OutputImage
)
Write-Host $message
