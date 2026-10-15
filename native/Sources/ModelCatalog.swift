import Foundation

struct ModelAsset: Sendable {
    let name: String
    let urlString: String
    let size: Int64?
    let checksum: String
    let checksumType: String

    init(name: String, url: String, size: Int64?, checksum: String, checksumType: String) {
        self.name = name
        self.urlString = url
        self.size = size
        self.checksum = checksum
        self.checksumType = checksumType
    }
}

enum SpeechModelCatalog {
    static let ids = SpeechModelID.allCases
    static let recommendedModel: SpeechModelID? = .parakeet

    static func directoryName(for id: SpeechModelID) -> String {
        switch id {
        case .moonshine: "moonshine-medium-streaming-en"
        case .parakeet: "parakeet-tdt-0.6b-v2-coreml"
        case .whisper: "whisper-large-v3-turbo"
        }
    }

    static func directory(for id: SpeechModelID, in modelsRoot: URL) -> URL {
        modelsRoot.appendingPathComponent(directoryName(for: id), isDirectory: true)
    }

    static func modelsRoot(from moonshineDirectory: URL) -> URL {
        moonshineDirectory.standardizedFileURL.deletingLastPathComponent()
    }

    static func makeEngine(for id: SpeechModelID) -> any SpeechEngine {
        switch id {
        case .moonshine: MoonshineEngine()
        case .parakeet: ParakeetEngine()
        case .whisper: WhisperEngine()
        }
    }

    static func assets(for id: SpeechModelID) throws -> [ModelAsset] {
        switch id {
        case .moonshine:
            try MoonshineCatalog.englishMediumStreamingFiles()
        case .parakeet: parakeetAssets
        case .whisper: whisperTurboAssets
        }
    }

    private static let parakeetAssets: [ModelAsset] = [
        ModelAsset(name: "Decoder.mlmodelc/analytics/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Decoder.mlmodelc/analytics/coremldata.bin?download=true", size: 243, checksum: "46de1a6fe2e49d19a2125bc91acf020df7f2aea84ba821532aade8427a440b05", checksumType: "sha256"),
        ModelAsset(name: "Decoder.mlmodelc/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Decoder.mlmodelc/coremldata.bin?download=true", size: 554, checksum: "d200ca07694a347f6d02a3886a062ae839831e094e443222f2e48a14945966a8", checksumType: "sha256"),
        ModelAsset(name: "Decoder.mlmodelc/metadata.json", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Decoder.mlmodelc/metadata.json?download=true", size: 3427, checksum: "90a279b822496316458febc0ce761ab05954fadd9d66aa97bea077a35fc8f2b2", checksumType: "sha256"),
        ModelAsset(name: "Decoder.mlmodelc/model.mil", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Decoder.mlmodelc/model.mil?download=true", size: 13106, checksum: "7b95a5a6b672c652000348a67b6d4d92bb8e176b978c6666fe73c28a4d7ec579", checksumType: "sha256"),
        ModelAsset(name: "Decoder.mlmodelc/weights/weight.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Decoder.mlmodelc/weights/weight.bin?download=true", size: 14429952, checksum: "27d26890221d82322c1092fd99d7b40578e435d5cf4b83c887c42603caf97aba", checksumType: "sha256"),
        ModelAsset(name: "Encoder.mlmodelc/analytics/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Encoder.mlmodelc/analytics/coremldata.bin?download=true", size: 243, checksum: "42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105", checksumType: "sha256"),
        ModelAsset(name: "Encoder.mlmodelc/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Encoder.mlmodelc/coremldata.bin?download=true", size: 485, checksum: "4def7aa848599ad0e17a8b9a982edcdbf33cf92e1f4b798de32e2ca0bc74b030", checksumType: "sha256"),
        ModelAsset(name: "Encoder.mlmodelc/metadata.json", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Encoder.mlmodelc/metadata.json?download=true", size: 2926, checksum: "58222fbc48c13c49d9715567803cd50cb9c23e4360462e0f8ffcea59a2c73c63", checksumType: "sha256"),
        ModelAsset(name: "Encoder.mlmodelc/model.mil", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Encoder.mlmodelc/model.mil?download=true", size: 959769, checksum: "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808", checksumType: "sha256"),
        ModelAsset(name: "Encoder.mlmodelc/weights/weight.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Encoder.mlmodelc/weights/weight.bin?download=true", size: 445187200, checksum: "4adc7ad44f9d05e1bffeb2b06d3bb02861a5c7602dff63a6b494aed3bf8a6c3e", checksumType: "sha256"),
        ModelAsset(name: "JointDecision.mlmodelc/analytics/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/JointDecision.mlmodelc/analytics/coremldata.bin?download=true", size: 243, checksum: "f1183ba213bb94a918c8d2cad19ab045320618f97f6ca662245b3936d7b090f7", checksumType: "sha256"),
        ModelAsset(name: "JointDecision.mlmodelc/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/JointDecision.mlmodelc/coremldata.bin?download=true", size: 534, checksum: "e2c6752f1c8cf2d3f6f26ec93195c9bfa759ad59edf9f806696a138154f96f11", checksumType: "sha256"),
        ModelAsset(name: "JointDecision.mlmodelc/metadata.json", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/JointDecision.mlmodelc/metadata.json?download=true", size: 2936, checksum: "ba8d309417b9acd4a175fdb15687de6a941db2f5b06666a60e7cf3cc8e2d3c3c", checksumType: "sha256"),
        ModelAsset(name: "JointDecision.mlmodelc/model.mil", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/JointDecision.mlmodelc/model.mil?download=true", size: 9722, checksum: "93bf82042235127cb81ab537dcae47a1c2e7e242ce4ffdaf772981b45eedc4f0", checksumType: "sha256"),
        ModelAsset(name: "JointDecision.mlmodelc/weights/weight.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/JointDecision.mlmodelc/weights/weight.bin?download=true", size: 3453388, checksum: "ca22a65903a05e64137677da608077578a8606090a598abf4875fa6199aaa19d", checksumType: "sha256"),
        ModelAsset(name: "Preprocessor.mlmodelc/analytics/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Preprocessor.mlmodelc/analytics/coremldata.bin?download=true", size: 243, checksum: "03ab3c1327a054c54c07a40325db967ec574f2c91dcc8192bfa44aa561bcf2d8", checksumType: "sha256"),
        ModelAsset(name: "Preprocessor.mlmodelc/coremldata.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Preprocessor.mlmodelc/coremldata.bin?download=true", size: 494, checksum: "d88ea1fc349459c9e100d6a96688c5b29a1f0d865f544be103001724b986b6d6", checksumType: "sha256"),
        ModelAsset(name: "Preprocessor.mlmodelc/metadata.json", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Preprocessor.mlmodelc/metadata.json?download=true", size: 2974, checksum: "fb16c581ff5e1b962e7cb2181ed892cd32f9f84c12b6e80ff3e089f28e35bcbb", checksumType: "sha256"),
        ModelAsset(name: "Preprocessor.mlmodelc/model.mil", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Preprocessor.mlmodelc/model.mil?download=true", size: 27166, checksum: "3e06d16fd061294c8a75be68c43a3b1ed1f593d4a9c35249e9cdbccadc59721e", checksumType: "sha256"),
        ModelAsset(name: "Preprocessor.mlmodelc/weights/weight.bin", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/Preprocessor.mlmodelc/weights/weight.bin?download=true", size: 298880, checksum: "a5f7df6c7f47147ae9486fe18cc7792f9a44d093ec3c6a11e91ef2dc363c48dc", checksumType: "sha256"),
        ModelAsset(name: "parakeet_vocab.json", url: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/ee09c569f73759e6d44c9bd16766f477b2b36d39/parakeet_vocab.json?download=true", size: 18762, checksum: "57019fe3c745772ca83a1b048a4bb951cd51329504ea33d4d83316b96e279a97", checksumType: "sha256")
    ]

    private static let whisperTurboAssets: [ModelAsset] = [
        ModelAsset(name: "ggml-large-v3-turbo.bin", url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo.bin?download=true", size: 1624555275, checksum: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69", checksumType: "sha256")
    ]
}
