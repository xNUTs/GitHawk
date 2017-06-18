//
//  CommentModelsFromMarkdown.swift
//  Freetime
//
//  Created by Ryan Nystrom on 6/14/17.
//  Copyright © 2017 Ryan Nystrom. All rights reserved.
//

import UIKit
import IGListKit
import MMMarkdown

private let newlineString = "\n"
private let bulletString = "\u{2022}"

func createCommentAST(markdown: String) -> MMDocument? {
    let parser = MMParser(extensions: .gitHubFlavored)
    var error: NSError? = nil
    let document = parser.parseMarkdown(markdown, error: &error)
    if let error = error {
        print("Error parsing markdown: %@", error.localizedDescription)
    }
    return document
}

func commentModels(markdown: String, width: CGFloat) -> [IGListDiffable] {
    guard let document = createCommentAST(markdown: markdown) else { return [] }

    var results = [IGListDiffable]()

    let baseAttributes: [String: Any] = [
        NSFontAttributeName: Styles.Fonts.body,
        NSForegroundColorAttributeName: Styles.Colors.Gray.dark,
        NSParagraphStyleAttributeName: {
            let para = NSMutableParagraphStyle()
            para.paragraphSpacingBefore = 12;
            return para
        }(),
        NSBackgroundColorAttributeName: UIColor.white
    ]

    let seedString = NSMutableAttributedString()

    for element in document.elements {
        travelAST(
            markdown: document.markdown,
            element: element,
            attributedString: seedString,
            attributeStack: baseAttributes,
            width: width,
            listLevel: 0,
            results: &results
        )
    }

    // add any remaining text
    if seedString.length > 0 {
        results.append(createTextModel(attributedString: seedString, width: width))
    }

    return results
}

private func createTextModel(
    attributedString: NSAttributedString,
    width: CGFloat
    ) -> NSAttributedStringSizing {
    // remove head/tail whitespace and newline from text blocks
    let trimmedString = attributedString
        .attributedStringByTrimmingCharacterSet(charSet: .whitespacesAndNewlines)
    return NSAttributedStringSizing(
        containerWidth: width,
        attributedText: trimmedString,
        inset: IssueCommentTextCell.inset
    )
}

public func substringOrNewline(text: String, range: NSRange) -> String {
    let substring = text.substring(with: range) ?? ""
    if substring.characters.count > 0 {
        return substring
    } else {
        return newlineString
    }
}

private func typeNeedsNewline(type: MMElementType) -> Bool {
    switch type {
    case .paragraph: return true
    case .listItem: return true
    case .header: return true
    default: return false
    }
}

private func createModel(markdown: String, element: MMElement) -> IGListDiffable? {
    switch element.type {
    case .codeBlock:
        return element.codeBlock(markdown: markdown)
    case .image:
        return element.imageModel
    default: return nil
    }
}

private func isList(type: MMElementType) -> Bool {
    switch type {
    case .bulletedList, .numberedList: return true
    default: return false
    }
}

private func travelAST(
    markdown: String,
    element: MMElement,
    attributedString: NSMutableAttributedString,
    attributeStack: [String: Any],
    width: CGFloat,
    listLevel: Int,
    results: inout [IGListDiffable]
    ) {
    let nextListLevel = listLevel + (isList(type: element.type) ? 1 : 0)

    // push more text attributes on the stack the deeper we go
    let pushedAttributes = element.attributes(currentAttributes: attributeStack, listLevel: nextListLevel)

    if typeNeedsNewline(type: element.type) {
        attributedString.append(NSAttributedString(string: newlineString, attributes: pushedAttributes))
    }

    if element.type == .none {
        let substring = substringOrNewline(text: markdown, range: element.range)
        attributedString.append(NSAttributedString(string: substring, attributes: pushedAttributes))
    } else if element.type == .lineBreak {
        attributedString.append(NSAttributedString(string: newlineString, attributes: pushedAttributes))
    } else if element.type == .listItem {
        // append list styles at the beginning of each list item
        let isInsideBulletedList = element.parent?.type == .bulletedList
        let modifier: String
        if isInsideBulletedList {
            modifier = "\(bulletString) "
        } else if element.numberedListPosition > 0 {
            modifier = "\(element.numberedListPosition). "
        } else {
            modifier = ""
        }
        attributedString.append(NSAttributedString(string: modifier, attributes: pushedAttributes))
    }

    let model = createModel(markdown: markdown, element: element)

    // if a model exists, push a new model with the current text stack _before_ the model. remember to drain the text
    if let model = model {
        results.append(createTextModel(attributedString: attributedString, width: width))
        results.append(model)
        attributedString.removeAll()
    } else {
        for child in element.children {
            travelAST(
                markdown: markdown,
                element: child,
                attributedString: attributedString,
                attributeStack: pushedAttributes,
                width: width,
                listLevel: nextListLevel,
                results: &results
            )
        }
    }
}
