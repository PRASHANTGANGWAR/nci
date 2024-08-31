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
    struct CampaignSettings {
        uint256 softCap;
        uint256 hardCap;
        uint256 campaignEndTime;
    }
    uint8 private decimal;
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
    uint256 private pricePercetnage = 100;
    address public networkFeeWallet;
    bool private  PRICE_INCREASED_AFTER_CAP_REACHED;
    bool public isSoftCapReached;
    bool public withdrawEnableOrNot;

    IERC20Extended public liquidityTokenContract;

    mapping(address => bool) public admin;
    mapping(address => bool) public signer;
    mapping(address => uint256) public nonces;

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

        _mint(address(this), _initialSupply);

        currentSupply = _initialSupply;
        softCap = _campaignSettings.softCap;
        hardCap = _campaignSettings.hardCap;

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

    modifier campaignComplete() {
        require(
            block.number >= campaignEndTime,
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

    // Function to purchase tokens during the campaign
    function buyTokens(uint256 _tokenAmount)
        external
        hardCapNotReachedOnly
    {
        _buyTokens(_tokenAmount, msg.sender);  
    }

    //  Function to purchase tokens during the campaign with delegate functionality
    function delegateBuyTokens(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee,  uint256 _nonce)
        external
        onlySigner
        hardCapNotReachedOnly
    {
        require(_tokenAmount > _networkFee, "Token value should be greater than network fee");
        _validateData(_signature,_investorAddress, _tokenAmount, _networkFee, _nonce);
        uint256 remainingToken = _tokenAmount - _networkFee;
        _buyTokens(remainingToken, _investorAddress);  
        liquidityTokenContract.safeTransferFrom(
            _investorAddress,
            networkFeeWallet,
            _networkFee
        );
        nonces[_investorAddress]++;

    }
    
    // Function to sell tokens after the campaign is completed
    function sellTokens(uint256 _tokenAmount)
        external
        campaignComplete
        isSoftCapReachedOnly
    {
        _withdraw(_tokenAmount, msg.sender, false, 0);
    }

    // Function to sell tokens after the campaign is completed
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
    
    // Admin or Owner withdraws funds in investor pool
    function withdrawByAdminOrOwner(uint256 _tokenAmount)
        external
        onlyAdminOrOwner
        isSoftCapReachedOnly
    {
        require(investorsPool >= _tokenAmount, "Insufficient liquidity in pool");

        liquidityTokenContract.safeTransfer(msg.sender, _tokenAmount);
        investorsPool -= _tokenAmount;

        emit WithdrawFund(msg.sender, _tokenAmount, block.timestamp);
    }


    // Admin or Owner withdraws funds in profit pool
    function withdrawFromProfitPool() external onlyAdminOrOwner {
        require(profitPool > 0, "Pool doesn't have enough balance");

        uint tokenValue = (tokenInCirculation * baseTokenPrice) / 10 ** liquidityTokenContract.decimals();
        require(profitPool >= tokenValue, "Pool doesn't have enough balance");

        uint remainingToken = profitPool - tokenValue;
        require(
            liquidityTokenContract.balanceOf(address(this)) >= remainingToken,
            "Not enough liquidity available"
        );

        liquidityTokenContract.safeTransfer(msg.sender, remainingToken);
        profitPool -= remainingToken;

        emit WithdrawFund(msg.sender, remainingToken, block.timestamp);
    }

    // Add profits to the contract, updating the base token price
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

        liquidityTokenContract.safeTransferFrom(
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

    // Add liquidity to the profit pool
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

        liquidityTokenContract.safeTransferFrom(
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

    // Internal withdraw function
    function _withdraw(uint256 _tokenAmount, address _investorAddress, bool _isDelegate, uint256 _networkFee) internal {
        require(profitPool > 0, "Please wait for the profit to be added to pool");

        require(
            _tokenAmount > 0 && balanceOf(_investorAddress) >= _tokenAmount,
            "Insufficient balance"
        );

        uint256 tokens = (_tokenAmount * baseTokenPrice) /
            10 ** liquidityTokenContract.decimals();
        require(profitPool >= tokens, "Insufficient tokens in pool. Please try with a different amount.");
        if(_isDelegate){
            tokens = tokens - _networkFee;
            liquidityTokenContract.safeTransferFrom(
            _investorAddress,
            networkFeeWallet,
            _networkFee
            );
        }
        liquidityTokenContract.safeTransfer(_investorAddress, tokens);

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

    // Override the decimals function to return custom decimals
    function decimals() public view virtual override returns (uint8) {
        return decimal;
    }

    // Update admin status
    function updateAdmin(address _admin, bool _value)
        external
        onlyAdminOrOwner
    {
        require(_admin != address(0), "Admin address cannot be zero address");
        admin[_admin] = _value;
        emit UpdateAdmin(_admin, _value);
    }

   // Update admin status
    function updateSigner(address _signer, bool _value)
        external
        onlyAdminOrOwner
    {   
        require(_signer != address(0), "Signer address cannot be zero address");
        signer[_signer] = _value;
        emit UpdateSigner(_signer, _value);
    }

  // Update soft status
    function updateSoftCap(uint256 _value) external onlyAdminOrOwner {
        require(!isSoftCapReached, "The soft cap has already been reached.");
        softCap = _value;
        if (currentSupply <= totalSupply() - _value) {
            isSoftCapReached = true;
            emit SoftCapReachecd(true);
        }
        emit UpdateSoftCap(_value);
    }

    //Update campaign end time
    function updateCampaignEndTime(uint256 _campaignEndTime) external onlyAdminOrOwner {
        require(_campaignEndTime > campaignStartTime, "End time must be greater than the start time");
        campaignEndTime = _campaignEndTime;
        emit CampaignEndTime(_campaignEndTime);
    }

    // update percentage
    function updatePercentage(uint256 _percentage) external onlyAdminOrOwner {
        percentage = _percentage;
        emit TokenValueIncreasePercentage(_percentage);
    }

    //enable or disable withdraw
    function updateWithdrawEnableOrDisable(bool _value) external onlyAdminOrOwner{
        withdrawEnableOrNot = _value;
        emit UpdateWithdrawlAccess(_value);
    }

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

    function _buyTokens(uint256 _tokenAmount, address _investorAddress) internal {
        require(_tokenAmount > 0, "The amount must be greater than zero.");
        require(
            liquidityTokenContract.allowance(_investorAddress, address(this)) >=
                _tokenAmount &&
                liquidityTokenContract.balanceOf(_investorAddress) >= _tokenAmount,
            "Insufficient allowance or balance"
        );
        uint tokenPrice = increseBaseTokenValue(isSoftCapReached);
        uint256 tokensToPurchase = (_tokenAmount * 10 ** decimal) /
            tokenPrice;
         require(
            tokensToPurchase <= hardCap,
            "Purchase denied. The requested amount exceeds the available tokens in the pool. Please try with a lower amount."
        );
        require(
            balanceOf(address(this)) >= tokensToPurchase,
            "Not enough tokens available in pool. Please try with a different amount."
        );

        liquidityTokenContract.safeTransferFrom(
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
            baseTokenPrice,
            block.timestamp
        );
    }

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

    function _validateInvestor(bytes32 _message, bytes memory signature)
        internal 
        pure
        returns (address)
    {
        _message = MessageHashUtils.toEthSignedMessageHash(_message);
        return ECDSA.recover(_message, signature);
    }
}
