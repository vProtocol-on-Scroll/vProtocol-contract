// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "../model/Protocol.sol";

library LibAppStorage {
    struct Layout {
        /// @dev maps collateral token to their price feed
        mapping(address token => address priceFeed) s_priceFeeds;
        /// @dev maps address of a token to see if it is loanable
        mapping(address token => bool isLoanable) s_isLoanable;
        /// @dev maps user to the value of balance he has collaterised
        mapping(address => mapping(address token => uint256 balance)) s_addressToCollateralDeposited;
        /// @dev maps user to the value of balance he has available
        mapping(address => mapping(address token => uint256 balance)) s_addressToAvailableBalance;
        /// @dev mapping the address of a user to its Struct
        mapping(address => User) addressToUser;
        /// @dev mapping of users to their address
        mapping(uint96 requestId => Request) request;
        /// @dev mapping a requestId to the collaterals used in a request
        mapping(uint96 requestId => mapping(address => uint256)) s_idToCollateralTokenAmount;
        /// @dev allowlist for spoke contracts
        mapping(uint16 => address) s_spokeProtocols;
        /// @dev wormhole message hashes
        mapping(bytes32 => bool) s_consumedMessages;
     
        /// @dev mapping of id to loanListing
        mapping(uint96 listingId => LoanListing) loanListings;
        /// @dev Collection of all colleteral Adresses
        address[] s_collateralToken;
        /// @dev all loanable assets
        address[] s_loanableToken;
        /// @dev request id;
        uint96 requestId;
        /// @dev the number of listings created
        uint96 listingId;
  
        /// @dev address of the bot that calls the liquidate function
        address botAddress;
        /// @dev uniswap router address
        address swapRouter;
    


//  COREPOOLCONFIG STATE VARIABLES        
     // Vault Management
    mapping(address => address) assetToVault; // assetAddress => vaultAddress
    mapping(address => VaultConfig) s_vaultConfigs;
    mapping(address => mapping(address => UserData)) s_userData; // user => vault => state
    // Protocol Configuration
    address s_protocolFeeRecipient;
    uint256 s_protocolFeeBps; // Shared fee across all vaults
    uint256 s_maxProtocolLTVBps;
    bool paused;


}






}
