//
//  InstalledAppsCollectionFooterView.swift
//  AltStore
//
//  Created by Riley Testut on 11/13/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import UIKit

class InstalledAppsCollectionFooterView: UICollectionReusableView
{
    static let nib = UINib(nibName: "InstalledAppsCollectionFooterView", bundle: nil)
    
    @IBOutlet var textLabel: UILabel!
    @IBOutlet var button: UIButton!
}
