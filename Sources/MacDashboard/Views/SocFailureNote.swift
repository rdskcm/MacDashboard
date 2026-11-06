// Views/SocFailureNote.swift
// SOC-DETAILS 2.5 (design 7.8): the CPU read-failure note, full width above the CPU / GPU pair. It sits outside the
// pair on purpose: inside the CPU card it would leave a matching hole in the GPU card. It is the only state that
// adds height. Mounted only while `CPUPageModel.failureNote` is non-nil.

import SwiftUI

/// Internal: the visual fixture renders it.
@MainActor
struct SocFailureNote: View {
    let model: AppModel

    var body: some View {
        if let note = CPUPageModel.make(cpuPageInput(model)).failureNote {
            SectionNote(tone: DS3.hot, text: note)
        }
    }
}
