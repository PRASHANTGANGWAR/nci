// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./IERC20Extended.sol";

contract NCIContract is ERC20, Ownable {
    using SafeERC20 for IERC20Extended;

    // structs
    struct CampaignSettings {
        uint256 softCap;
        uint256 hardCap;
        uint256 campaignEndTime;
    }

    // private variables
    uint8 private decimal;
    uint256 private pricePercetnage = 100;
    bool private  PRICE_INCREASED_AFTER_CAP_REACHED;

    // public variables
    uint256 public baseTokenPrice;
    uint256 public currentSupply;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public investorsPool;
    uint256 public profitPool;
    uint256 public campaignStartTime;
    uint256 public campaignEndTime;
    uint256 public totalRaised;
    uint256 public tokenInCirculation;
    uint256 public percentage = 100;
    address public networkFeeWallet;
    bool public isSoftCapReached;
    bool public withdrawEnableOrNot;

    IERC20Extended public liquidityTokenContract;

    //mappings
    mapping(address => bool) public admin;
    mapping(address => bool) public signer;
    mapping(address => uint256) public nonces;

    // events 
    event TokensPurchased(
        address indexed investor,
        uint256 liquidityTokenAmount,
        uint256 tokenAmount,
        uint256 baseTokenPrice,
        uint256 blockTimestamp
    );
    event ProfitAdded(
        address indexed ownerAdminAddress,
        uint256 amount,
        uint256 blockTimestamp
    );
    event BaseTokenPriceUpdated(uint256 newPrice);
    event InvestmentWithdrawl(
        address indexed investor,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount,
        uint256 blockTimestamp,
        uint256 newProfitPool
    );
    event WithdrawFund(
        address indexed ownerAdminAddress,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event UpdateAdmin(address indexed adminAddress, bool value);
    event UpdateSigner(address indexed signerAddress, bool value);
    event AddLiquidity(
        address indexed ownerAdminAddress,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event UpdateSoftCap(uint256 value);
    event SoftCapReachecd(bool value);
    event CampaignEndTime(uint256 campaignEndTime);
    event TokenValueIncreasePercentage(uint256 percentage);
    event UpdateWithdrawlAccess(bool value);
    event UpdateFeeWallet(address feeWallet);
    event WitdrawLiquidity(address ownerAdminAddress, uint256 tokenAmount, uint256 blockTimestamp);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        CampaignSettings memory _campaignSettings,
        uint8 _decimal,
        address _liquidityTokenContract,
        address _initialOwner,
        address _admin,
        address _signer,
        address _networkFeeWallet
    ) Ownable(_initialOwner) ERC20(_name, _symbol) {
        require(
            _campaignSettings.campaignEndTime > block.number,
            "Campaign duration must be greater than current block number"
        );
        require(_campaignSettings.softCap < _campaignSettings.hardCap, "Soft cap must be less than hard cap");

        _mint(address(this), _initialSupply * (10 **_decimal));

        currentSupply = _initialSupply * (10 **_decimal);
        softCap = _campaignSettings.softCap * (10 **_decimal);
        hardCap = _campaignSettings.hardCap * (10 **_decimal);

        isSoftCapReached = false;
        liquidityTokenContract = IERC20Extended(_liquidityTokenContract);
        baseTokenPrice =
            5 *
            (10**IERC20Extended(_liquidityTokenContract).decimals());
        decimal = _decimal;
        campaignStartTime = block.number;
        campaignEndTime = _campaignSettings.campaignEndTime;
        admin[_admin] = true;
        withdrawEnableOrNot = false;
        signer[_signer] = true;
        networkFeeWallet = _networkFeeWallet;
    }

    // modifiers
    modifier campaignComplete() {
        require(
            block.number > campaignEndTime,
            "The campaign has not been completed."
        );
        _;
    }

    modifier isSoftCapReachedOnly() {
        require(isSoftCapReached, "The soft cap has not been met.");
        _;
    }

    modifier hardCapNotReachedOnly() {
        require(totalRaised < hardCap, "Cannot buy tokens: Hard cap reached.");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(admin[msg.sender] || msg.sender == owner(), "Unauthorized");
        _;
    }


    modifier withdrawEnabledOrNot() {
            require(withdrawEnableOrNot, "Withdrawals are disabled.");
        _;
    }

    modifier onlySigner() {
            require(signer[msg.sender], "Only signer is allowed");
        _;
    }

    /// @notice Allows users to buy tokens if the hard cap is not reached.
    /// @param _tokenAmount Amount of tokens to purchase.
    function buyTokens(uint256 _tokenAmount)
        external
        hardCapNotReachedOnly
    {
        _buyTokens(_tokenAmount, msg.sender);  
    }

    /// @notice Allows a signer to buy tokens for an investor, deducting network fees.
    /// @param _signature Signature for transaction validation.
    /// @param _investorAddress Address of the token recipient.
    /// @param _tokenAmount Total tokens to deposit.
    /// @param _networkFee Fee deducted from the token amount.
    /// @param _nonce Prevents replay attacks.
    function delegateBuyTokens(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee,  uint256 _nonce)
        external
        onlySigner
        hardCapNotReachedOnly
    {
        require(_tokenAmount > _networkFee, "Token value should be greater than network fee");
        _validateData(_signature,_investorAddress, _tokenAmount, _networkFee, _nonce);
        uint256 remainingToken = _tokenAmount - _networkFee;
        _buyTokens(remainingToken, _investorAddress);  

        SafeERC20.safeTransferFrom(
            liquidityTokenContract,
            _investorAddress,
            networkFeeWallet,
            _networkFee
        );
        nonces[_investorAddress]++;

    }
    
    /// @notice Allows users to sell tokens after the campaign is complete and soft cap is reached.
    /// @param _tokenAmount Amount of tokens to sell.
    /// @dev The function checks that the campaign is complete and the soft cap has been reached.
    /// @dev Internally calls `_withdraw` to handle the withdrawal logic.
    function sellTokens(uint256 _tokenAmount)
        external
        campaignComplete
        isSoftCapReachedOnly
    {
        _withdraw(_tokenAmount, msg.sender, false, 0);
    }

    /// @notice Allows a signer to sell tokens for an investor, deducting network fees.
    /// @param _signature Signature for validation.
    /// @param _investorAddress Address of the token seller.
    /// @param _tokenAmount Tokens to sell.
    /// @param _networkFee Fee deducted from the amount.
    /// @param _nonce Prevents replay attacks.
    function delegateSellTokens(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee,  uint256 _nonce)
        external
        onlySigner
        campaignComplete
        isSoftCapReachedOnly
    {
        _validateData(_signature,_investorAddress, _tokenAmount, _networkFee, _nonce);
        _withdraw(_tokenAmount, _investorAddress,  true, _networkFee);
        nonces[_investorAddress]++;

    }
    
    /// @notice Admin or owner can withdraw tokens if the soft cap is reached.
    /// @param _tokenAmount Amount of tokens to withdraw.
    function withdrawByAdminOrOwner(uint256 _tokenAmount)
        external
        onlyAdminOrOwner
        isSoftCapReachedOnly
    {
        require(investorsPool >= _tokenAmount, "Insufficient liquidity in pool");

        SafeERC20.safeTransfer(liquidityTokenContract, msg.sender, _tokenAmount);
        investorsPool -= _tokenAmount;

        emit WithdrawFund(msg.sender, _tokenAmount, block.timestamp);
    }


    /// @notice Admin or owner withdraws tokens from the profit pool.
    /// @dev Checks if the profit pool has enough balance and liquidity is sufficient.
    /// @dev Calculates the token value based on `tokenInCirculation` and `baseTokenPrice`.
    /// @dev Transfers remaining tokens to the caller and updates the pool balance.
    /// @dev Emits a `WithdrawFund` event after successful withdrawal.
    function withdrawFromProfitPool() external onlyAdminOrOwner {
        require(profitPool > 0, "Pool doesn't have enough balance");

        uint tokenValue = (tokenInCirculation * baseTokenPrice) / 10 ** liquidityTokenContract.decimals();
        require(profitPool >= tokenValue, "Pool doesn't have enough balance");

        uint remainingToken = profitPool - tokenValue;
        require(
            liquidityTokenContract.balanceOf(address(this)) >= remainingToken,
            "Not enough liquidity available"
        );

        SafeERC20.safeTransfer(liquidityTokenContract, msg.sender, remainingToken);
        profitPool -= remainingToken;

        emit WithdrawFund(msg.sender, remainingToken, block.timestamp);
    }

    /// @notice Admin or owner adds profit to the pool and updates the base token price.
    /// @param _profitAmount Amount of profit to add.  
    function addProfit(uint256 _profitAmount)
        external
        onlyAdminOrOwner
        isSoftCapReachedOnly
    {
        require(
            _profitAmount > 0 && tokenInCirculation > 0,
            "Profit amount and total token in circulation must both be greater than zero."
        );
        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _profitAmount &&
                liquidityTokenContract.balanceOf(msg.sender) >= _profitAmount,
            "Insufficient allowance or balance"
        );

        SafeERC20.safeTransferFrom(
            liquidityTokenContract,
            msg.sender,
            address(this),
            _profitAmount
        );
        profitPool += _profitAmount;
        uint256 newTokenValue = calculateNewTokenValue(baseTokenPrice,_profitAmount);
        baseTokenPrice += newTokenValue;

        emit BaseTokenPriceUpdated(baseTokenPrice);
        emit ProfitAdded(msg.sender, _profitAmount, block.timestamp);
    }

    /// @notice Admin or owner adds liquidity to the profit pool.
    /// @param _tokenAmount Amount of tokens to add
    function addLiquidity(uint256 _tokenAmount)
        external
        onlyAdminOrOwner
        isSoftCapReachedOnly
        campaignComplete
    {
        require(_tokenAmount > 0, "Amount must be greater than zero.");
        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _tokenAmount &&
                liquidityTokenContract.balanceOf(msg.sender) >= _tokenAmount,
            "Insufficient allowance or balance"
        );

        SafeERC20.safeTransferFrom(
            liquidityTokenContract,
            msg.sender,
            address(this),
            _tokenAmount
        );
        profitPool += _tokenAmount;

        emit AddLiquidity(msg.sender, _tokenAmount, block.timestamp);
    }

    // Withdraw funds for investors
    function withdrawInvestment(uint256 _tokenAmount)
        external
        withdrawEnabledOrNot
    {
        _withdraw(_tokenAmount, msg.sender, false, 0);
    }

    /// @notice Handles token withdrawal from the profit pool, including network fees if applicable.
    /// @param _tokenAmount Amount of tokens to withdraw.
    /// @param _investorAddress Address of the investor.
    /// @param _isDelegate Indicates if the withdrawal is by a delegate.
    /// @param _networkFee Fee deducted if `_isDelegate` is true.
    function _withdraw(uint256 _tokenAmount, address _investorAddress, bool _isDelegate, uint256 _networkFee) internal {
        require(profitPool > 0, "Please wait for the profit to be added to pool");

        require(
            _tokenAmount > 0 && balanceOf(_investorAddress) >= _tokenAmount,
            "Insufficient balance"
        );

        uint256 tokens = (_tokenAmount * baseTokenPrice) /
            10 ** liquidityTokenContract.decimals();
        require(profitPool >= tokens, "Insufficient tokens in pool. Please try with a different amount.");
        if (_isDelegate) {
        uint256 remainingToken = tokens - _networkFee;
        SafeERC20.safeTransfer(liquidityTokenContract, networkFeeWallet, _networkFee);
        SafeERC20.safeTransfer(liquidityTokenContract, _investorAddress, remainingToken);
        } else {
            SafeERC20.safeTransfer(liquidityTokenContract, _investorAddress, tokens);
        }

        // burn dmng token
        _burn(_investorAddress, _tokenAmount);
        profitPool -= tokens;
        tokenInCirculation -= _tokenAmount;

        emit InvestmentWithdrawl(
            _investorAddress,
            _tokenAmount,
            tokens,
            block.timestamp,
            profitPool
        );
    }

    /// @notice Calculates the increase in token value based on profit and supply.
    /// @param _baseTokenPrice Current token price.
    /// @param _profitAmount Amount of profit to include.
    function calculateNewTokenValue(uint _baseTokenPrice, uint256 _profitAmount)
        public
        view
        returns (uint256)
    {
        uint256 newTokenPrice = ((_profitAmount * 10 ** liquidityTokenContract.decimals()) /
            (tokenInCirculation + currentSupply)) ; 
        uint256 increment = (_baseTokenPrice * percentage) / 1000; 
        if(newTokenPrice >=  increment ){
            return increment;
        }
        return newTokenPrice;
    }

    /// @notice Returns the number of decimals used by the token.
    /// @return The number of decimal places.
    function decimals() public view virtual override returns (uint8) {
        return decimal;
    }

    /// @notice Updates admin status for an address.
    /// @param _admin Address to update.
    /// @param _value New admin status (true/false).
    function updateAdmin(address _admin, bool _value)
        external
        onlyAdminOrOwner
    {
        require(_admin != address(0), "Admin address cannot be zero address");
        admin[_admin] = _value;
        emit UpdateAdmin(_admin, _value);
    }

    /// @notice Updates signer status for an address.
    /// @param _signer Address to update.
    /// @param _value New signer status (true/false).
    function updateSigner(address _signer, bool _value)
        external
        onlyAdminOrOwner
    {   
        require(_signer != address(0), "Signer address cannot be zero address");
        signer[_signer] = _value;
        emit UpdateSigner(_signer, _value);
    }

    /// @notice Updates the soft cap value and checks if it has been reached.
    /// @param _value New soft cap amount.
    /// @dev Requires the caller to be an admin or owner.
    /// @dev Marks the soft cap as reached if the current supply is below or equal to the target supply.
    /// @dev Emits `SoftCapReachecd` and `UpdateSoftCap` events.
    function updateSoftCap(uint256 _value) external onlyAdminOrOwner {
        require(!isSoftCapReached, "The soft cap has already been reached.");
        softCap = _value;
        if (currentSupply <= totalSupply() - _value) {
            isSoftCapReached = true;
            emit SoftCapReachecd(true);
        }
        emit UpdateSoftCap(_value);
    }

    /// @notice Updates the campaign end time.
    /// @param _campaignEndTime New end time for the campaign.
    /// @dev Requires the end time to be greater than the start time.
    /// @dev Emits a `CampaignEndTime` event.
    function updateCampaignEndTime(uint256 _campaignEndTime) external onlyAdminOrOwner {
        require(_campaignEndTime > campaignStartTime, "End time must be greater than the start time");
        campaignEndTime = _campaignEndTime;
        emit CampaignEndTime(_campaignEndTime);
    }

    /// @notice Updates the percentage used for token value increases.
    /// @param _percentage New percentage value.
    /// @dev Emits a `TokenValueIncreasePercentage` event.
    function updatePercentage(uint256 _percentage) external onlyAdminOrOwner {
        percentage = _percentage;
        emit TokenValueIncreasePercentage(_percentage);
    }

    /// @notice Enables or disables the withdrawal functionality.
    /// @param _value `true` to enable, `false` to disable.
    /// @dev Emits an `UpdateWithdrawlAccess` event.
    function updateWithdrawEnableOrDisable(bool _value) external onlyAdminOrOwner{
        withdrawEnableOrNot = _value;
        emit UpdateWithdrawlAccess(_value);
    }

    /// @notice Increases the base token value if conditions are met.
    /// @param _isSoftCapReached Whether the soft cap is reached.
    /// @return Updated base token price.

    function increseBaseTokenValue(bool _isSoftCapReached) internal returns(uint256) {
        if(_isSoftCapReached && block.number > campaignEndTime && !PRICE_INCREASED_AFTER_CAP_REACHED){
            uint256 increment = (baseTokenPrice * pricePercetnage) / 1000; 
            baseTokenPrice += increment;
            PRICE_INCREASED_AFTER_CAP_REACHED = true;
            emit  BaseTokenPriceUpdated(baseTokenPrice);
            return baseTokenPrice;
        }
        return baseTokenPrice;
    }

    /// @notice Processes token purchase for an investor.
    /// @param _tokenAmount Amount of liquidity tokens.
    /// @param _investorAddress Address buying tokens.
    function _buyTokens(uint256 _tokenAmount, address _investorAddress) internal {
        require(_tokenAmount > 0, "The amount must be greater than zero.");
        require(
            liquidityTokenContract.allowance(_investorAddress, address(this)) >=
                _tokenAmount &&
                liquidityTokenContract.balanceOf(_investorAddress) >= _tokenAmount,
            "Insufficient allowance or balance"
        );
        uint tokenPrice = increseBaseTokenValue(isSoftCapReached);
        uint256 tokensToPurchase = (_tokenAmount * 10 ** liquidityTokenContract.decimals()) /
            tokenPrice;
         require(
            tokensToPurchase <= hardCap,
            "Purchase denied. The requested amount exceeds the available tokens in the pool. Please try with a lower amount."
        );
        require(
            balanceOf(address(this)) >= tokensToPurchase,
            "Not enough tokens available in pool. Please try with a different amount."
        );

        SafeERC20.safeTransferFrom(
            liquidityTokenContract,
            _investorAddress,
            address(this),
            _tokenAmount
        );
        investorsPool += _tokenAmount;
        currentSupply -= tokensToPurchase;
        totalRaised += tokensToPurchase;
        tokenInCirculation += tokensToPurchase;

        _transfer(address(this), _investorAddress, tokensToPurchase);
        if (!isSoftCapReached && currentSupply <= totalSupply() - softCap) {
            isSoftCapReached = true;
            emit SoftCapReachecd(true);
        }

        emit TokensPurchased(
            _investorAddress,
            _tokenAmount,
            tokensToPurchase,
            tokenPrice,
            block.timestamp
        );
    }

    /// @notice Validates transaction data including nonce and signature.
    /// @param _signature Signature for verification.
    /// @param _investorAddress Investor's address.
    /// @param _tokenAmount Amount of tokens.
    /// @param _networkFee Network fee.
    /// @param _nonce Nonce for replay protection.
    function _validateData(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee,  uint256 _nonce) internal view {
        require(_nonce == nonces[_investorAddress], "Invalid nonce");
        bytes32 message = keccak256(
            abi.encode(
                _investorAddress,
                _tokenAmount,
                baseTokenPrice,
                _networkFee,
                _nonce
            )
        );
        address investorAddress = _validateInvestor(message, _signature);  
        require(investorAddress == _investorAddress, "Invalid data");
    }

    /// @notice Recovers the investor's address from a signed message.
    /// @param _message Hashed message to recover from.
    /// @param signature Signature for verification.
    /// @return Address of the signer.
    /// @dev Converts the message to an Ethereum signed message hash and recovers the signer address.

    function _validateInvestor(bytes32 _message, bytes memory signature)
        internal 
        pure
        returns (address)
    {
        _message = MessageHashUtils.toEthSignedMessageHash(_message);
        return ECDSA.recover(_message, signature);
    }

    /// @notice Updates the wallet address for collecting network fees.
    /// @param _feeWallet New network fee wallet address.
    /// @dev Requires the caller to be an admin or owner.
    /// @dev Emits an `UpdateFeeWallet` event.
    function updateNetworkFeeWallet(address _feeWallet) external onlyAdminOrOwner{
        networkFeeWallet = _feeWallet;
        emit UpdateFeeWallet(_feeWallet);
    }

    /// @notice Allows admin or owner to withdraw all liquidity from the contract.
    /// @dev Transfers all liquidity tokens to the caller, resets profit and investor pools.
    /// @dev Emits a `WitdrawLiquidity` event.
    function witdrawLiquidity() external onlyAdminOrOwner {
        uint256 liquidityBalance = liquidityTokenContract.balanceOf(address(this));
        require(liquidityBalance > 0, "Insufficient liquidity in pool");
        SafeERC20.safeTransfer(liquidityTokenContract, msg.sender, liquidityBalance);
        profitPool = 0;
        investorsPool = 0;
        emit WitdrawLiquidity(msg.sender, liquidityBalance, block.timestamp);
    }
    
    function proof(address _investorAddress, uint256 _tokenAmount, uint256 _networkFee, uint256 _nonce) external view returns (bytes32) {
            bytes32 message = keccak256(
            abi.encode(
                _investorAddress,
                _tokenAmount,
                baseTokenPrice,
                _networkFee,
                _nonce
            )
        );
        return  message;
    }
}
