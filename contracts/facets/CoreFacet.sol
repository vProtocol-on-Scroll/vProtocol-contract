// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {AppStorage} from "../utils/functions/AppStorage.sol";
import {CoreVault} from "./CoreVault.sol";
import "../utils/validators/Error.sol";
import "../model/Event.sol";
import "../model/Protocol.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {PauseableFacet} from "../facets/PauseableFacet.sol";

contract CoreFacet is ReentrancyGuard, AppStorage, PauseableFacet {
    using SafeERC20 for IERC20;

    // ========== DEPOSIT FUNCTION ========== //

    event AssetSupplied(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);



/**
 * @notice Deposits specified asset into the corresponding ERC-4626 vault, minting shares to receiver
 * @dev Handles both native ETH and ERC20 tokens with proper validation
 * @param asset Address of the asset to deposit (address(1) for ETH)
 * @param _receiver Address to receive vault shares
 * @param _amount Amount of assets to deposit (ignored for ETH)
 * @return _shares Amount of vault shares minted
 */
function depositCollateral(
    IERC20 asset,
    address _receiver,
    uint256 _amount
) external payable nonReentrant protocolNotPaused returns (uint256 _shares) {
    // Validate input parameters
    Validator._validateSupplyParameters(address(asset), _receiver, _amount);

    address vaultAddress = _appStorage.assetToVault[ address(asset)];

    if (vaultAddress == address(0)) revert Protocol__AssetNotFound();
    // Cache vault instance

    CoreVault vault = CoreVault(payable(vaultAddress));

    bool isNativeToken = (address(asset) == address(1));

    if (isNativeToken) {
        // ETH deposit validation
        if (msg.value == 0) revert Protocol__InvalidAmount();
        _amount = msg.value;

        uint256 balanceBefore = address(vault).balance;
        _shares = vault.depositETH{value: msg.value}(_receiver);

        // Ensure ETH was received
        if (address(vault).balance < balanceBefore + msg.value) {
            revert Protocol__DepositFailed();
        }

    } else {        
        // Ensure sufficient balance
        if (asset.balanceOf(msg.sender) < _amount) {
            revert Protocol__InsufficientBalance();
        }
        uint256 balanceBefore = asset.balanceOf(vaultAddress);
        // Call vault deposit (vault internally handles safeTransferFrom)
        _shares = vault.deposit(_amount, _receiver);

        // Ensure tokens were received
        if (asset.balanceOf(vaultAddress) < balanceBefore + _amount) {
            revert Protocol__DepositFailed();
        }
    }

    // Update protocol state
    _appStorage.s_vaultConfigs[vaultAddress].totalDeposits += _amount;

    // Update user position
    UserData storage _userData = _appStorage.s_userData[_receiver][vaultAddress];
    _userData.depositedAssets += _amount;
    _userData.shares += _shares;

     emit AssetSupplied(_receiver, address(asset), _amount, _shares);
    return _shares;
}





}