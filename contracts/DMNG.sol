// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./IERC20Extended.sol";
import "./ErrorMessages.sol";

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
    bool public withdrawalAllowed;

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
    event UpdateWithdrawlStatus(bool value);
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
            ErrorMessages.E1
        );
        require(_campaignSettings.softCap < _campaignSettings.hardCap, ErrorMessages.E2);

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
        withdrawalAllowed = false;
        signer[_signer] = true;
        networkFeeWallet = _networkFeeWallet;
    }

    // modifiers
    modifier campaignComplete() {
        require(
            block.number > campaignEndTime,
            ErrorMessages.E3
        );
        _;
    }

    modifier isSoftCapReachedOnly() {
        require(isSoftCapReached, ErrorMessages.E4);
        _;
    }

    modifier hardCapNotReachedOnly() {
        require(totalRaised < hardCap, ErrorMessages.E5);
        _;
    }

    modifier onlyAdminOrOwner() {
        require(admin[msg.sender] || msg.sender == owner(), "Unauthorized");
        _;
    }


    modifier onlyIfWithdrawalsAllowed() {
            require(withdrawalAllowed, ErrorMessages.E6);
        _;
    }

    modifier onlySigner() {
            require(signer[msg.sender], ErrorMessages.E7);
        _;
    }

    modifier amountGreaterThanZero(uint256 _tokenAmount) {
    require(_tokenAmount > 0, ErrorMessages.E8);
    _;
}


    /**
     * @dev Allows an investor to buy tokens.
     * @param _tokenAmount Amount of tokens to purchase.
     * require Hard cap must not be reached and token amount must be greater than zero.
    */
    function buyTokens(uint256 _tokenAmount)
        external
        hardCapNotReachedOnly
        amountGreaterThanZero(_tokenAmount)
    {
        _buyTokens(_tokenAmount, msg.sender);  
    }

    /**
     * @dev Allows a signer to buy tokens on behalf of an investor.
     * @param _signature Authorization signature.
     * @param _investorAddress Investor's address.
     * @param _tokenAmount Total tokens to buy.
     * @param _networkFee Transaction fee.
     * @param _nonce Nonce for replay protection.
    */
    function delegateBuyTokens(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee,  uint256 _nonce)
        external
        onlySigner
        hardCapNotReachedOnly
        amountGreaterThanZero(_tokenAmount)
    {
        require(_tokenAmount > _networkFee, ErrorMessages.E9);
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
    
    /**
     * @dev Allows an investor to sell tokens.
     * @param _tokenAmount Amount of tokens to sell.
     * require The campaign must be complete and the soft cap must be reached.
     * require Token amount must be greater than zero.
    */
    function sellTokens(uint256 _tokenAmount)
        external
        campaignComplete
        isSoftCapReachedOnly
        amountGreaterThanZero(_tokenAmount)
    {
        uint256 tokens = _validateTokenTransaction(msg.sender, _tokenAmount);
        _withdraw(_tokenAmount, msg.sender, tokens, tokens);
    }

    /**
     * @dev Allows a signer to sell tokens on behalf of an investor.
     * @param _signature Authorization signature.
     * @param _investorAddress Address of the investor.
     * @param _tokenAmount Amount of tokens to sell.
     * @param _networkFee Fee for processing the sale.
     * @param _nonce Nonce for replay protection.
    */
    function delegateSellTokens(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee,  uint256 _nonce)
        external
        onlySigner
        campaignComplete
        isSoftCapReachedOnly
        amountGreaterThanZero(_tokenAmount)
    {
        _validateData(_signature,_investorAddress, _tokenAmount, _networkFee, _nonce);
        uint256 tokens = _validateTokenTransaction(_investorAddress,_tokenAmount );
        require(_networkFee < tokens, ErrorMessages.E10);
        uint256 remainingToken = tokens - _networkFee;
        handleNetworkFee(_networkFee);
        _withdraw(_tokenAmount, _investorAddress, tokens,  remainingToken);
        nonces[_investorAddress]++;

    }
    
    /**
     * @dev Allows admin or owner to withdraw funds from the investor pool.
     * @param _tokenAmount The amount of tokens to withdraw.
     * require Soft cap must be reached and the token amount must be greater than zero.
     * require The investor pool must have sufficient funds.
    */
    function withdrawFromInvestorPool(uint256 _tokenAmount)
        external
        onlyAdminOrOwner
        isSoftCapReachedOnly
        amountGreaterThanZero(_tokenAmount)
    {
        require(investorsPool >= _tokenAmount, ErrorMessages.E11);

        SafeERC20.safeTransfer(liquidityTokenContract, msg.sender, _tokenAmount);
        investorsPool -= _tokenAmount;

        emit WithdrawFund(msg.sender, _tokenAmount, block.timestamp);
    }


    /**
     * @dev Allows admin or owner to withdraw funds from the profit pool.
     * require Profit pool must be greater than zero.
     * require The token value must be less than or equal to the profit pool.
     * require The contract must have sufficient balance for the withdrawal.
     */
    function withdrawFromProfitPool() external onlyAdminOrOwner {
        require(profitPool > 0, ErrorMessages.E12);

        uint tokenValue = (tokenInCirculation * baseTokenPrice) / 10 ** liquidityTokenContract.decimals();
        require(profitPool >= tokenValue, ErrorMessages.E12);

        uint remainingToken = profitPool - tokenValue;
        require(
            liquidityTokenContract.balanceOf(address(this)) >= remainingToken,
           ErrorMessages.E13
        );

        SafeERC20.safeTransfer(liquidityTokenContract, msg.sender, remainingToken);
        profitPool -= remainingToken;

        emit WithdrawFund(msg.sender, remainingToken, block.timestamp);
    }

    /**
     * @dev Allows admin or owner to add profit to the profit pool and adjust the base token price.
     * @param _profitAmount The amount of profit to add.
     * require Soft cap must be reached and the profit amount must be greater than zero.
     * require The sender must have sufficient allowance and balance.
    */
    function addProfit(uint256 _profitAmount)
        external
        onlyAdminOrOwner
        isSoftCapReachedOnly
        amountGreaterThanZero(_profitAmount)
    {
        require(
             tokenInCirculation > 0,
             ErrorMessages.E14
        );
        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _profitAmount &&
                liquidityTokenContract.balanceOf(msg.sender) >= _profitAmount,
           ErrorMessages.E15
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

    /**
     * @dev Allows admin or owner to add liquidity to the contract.
     * @param _tokenAmount The amount of liquidity tokens to add.
     * require Soft cap must be reached and the campaign must be complete.
     * require Token amount must be greater than zero.
     * require The sender must have sufficient allowance and balance.
    */
    function addLiquidity(uint256 _tokenAmount)
        external
        onlyAdminOrOwner
        isSoftCapReachedOnly
        campaignComplete
        amountGreaterThanZero(_tokenAmount)
    {
        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _tokenAmount &&
                liquidityTokenContract.balanceOf(msg.sender) >= _tokenAmount,
            ErrorMessages.E15
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


    /**
     * @dev Allows the owner to withdraw all liquidity tokens from the contract.
     * require The contract must hold a non-zero liquidity balance.
     * Resets the profit pool and investors pool to zero.
     */
    function withdrawLiquidity() external onlyOwner {
        uint256 liquidityBalance = liquidityTokenContract.balanceOf(address(this));
        require(liquidityBalance > 0, ErrorMessages.E16);
        SafeERC20.safeTransfer(liquidityTokenContract, msg.sender, liquidityBalance);
        profitPool = 0;
        investorsPool = 0;
        emit WitdrawLiquidity(msg.sender, liquidityBalance, block.timestamp);
    }

    /**
     * @dev Allows an investor to withdraw their investment.
     * @param _tokenAmount The amount of tokens to withdraw.
     * require Withdrawals must be allowed.
     * require Token amount must be greater than zero.
    */
    function withdrawInvestment(uint256 _tokenAmount)
        external
        onlyIfWithdrawalsAllowed
        amountGreaterThanZero(_tokenAmount)
    {
       uint256 tokens =  _validateTokenTransaction(msg.sender, _tokenAmount);
        _withdraw(_tokenAmount, msg.sender, tokens, tokens);
    }

    /**
     * @dev Allows a signer to withdraw investment on behalf of an investor.
     * @param _signature The signature to authorize the withdrawal.
     * @param _investorAddress The address of the investor.
     * @param _tokenAmount The amount of tokens to withdraw.
     * @param _networkFee The fee for processing the withdrawal.
     * @param _nonce Nonce for replay protection.
     */
    function delegateWithdrawInvestment(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee, uint256 _nonce)
        external
        onlyIfWithdrawalsAllowed
        onlySigner
        amountGreaterThanZero(_tokenAmount)
    {
        _validateData(_signature,_investorAddress, _tokenAmount, _networkFee, _nonce);
        uint256 tokens = _validateTokenTransaction(_investorAddress, _tokenAmount);
        require(_networkFee <= tokens, ErrorMessages.E10);
        uint256 remainingTokens = tokens - _networkFee;
        handleNetworkFee(_networkFee);
        _withdraw(_tokenAmount, _investorAddress,  tokens, remainingTokens);
        nonces[_investorAddress]++;
    }

    /**
     * @dev Processes a withdrawal for an investor, including token transfer and burn.
     * @param _tokenAmount Amount of DMNG tokens to burn.
     * @param _investorAddress Address of the investor.
     * @param _tokens Amount of tokens to withdraw from the profit pool.
     * @param _remainingToken Amount of liquidity tokens to transfer to the investor.
    */
    function _withdraw(uint256 _tokenAmount, address _investorAddress, uint256 _tokens, uint256 _remainingToken) internal {
        SafeERC20.safeTransfer(liquidityTokenContract, _investorAddress, _remainingToken);

        // burn dmng token
        _burn(_investorAddress, _tokenAmount);
        profitPool -= _tokens;
        tokenInCirculation -= _tokenAmount;

        emit InvestmentWithdrawl(
            _investorAddress,
            _tokenAmount,
            _remainingToken,
            block.timestamp,
            profitPool
        );
    }


    /**
     * @dev Calculates the new token value based on profit and base price.
     * @param _baseTokenPrice The current base token price.
     * @param _profitAmount The amount of profit to consider.
     * @return The new token price, adjusted by profit and percentage.
    */
    function calculateNewTokenValue(uint _baseTokenPrice, uint256 _profitAmount)
        internal
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

    /**
     * @dev Returns the number of decimals used by the token.
     * @return The number of decimal places for the token.
    */
    function decimals() public view virtual override returns (uint8) {
        return decimal;
    }

    /**
     * @dev Sets or clears an admin's status.
     * @param _admin The address of the admin to update.
     * @param _value True to authorize, false to revoke.
     * require The admin address must be non-zero.
     */
    function updateAdmin(address _admin, bool _value)
        external
        onlyAdminOrOwner
    {
        require(_admin != address(0), ErrorMessages.E17);
        admin[_admin] = _value;
        emit UpdateAdmin(_admin, _value);
    }

    /**
     * @dev Updates the status of a signer.
     * @param _signer Address of the signer.
     * @param _value New status for the signer (true or false).
     * require Signer address must not be zero.
    */
    function updateSigner(address _signer, bool _value)
        external
        onlyAdminOrOwner
    {   
        require(_signer != address(0), ErrorMessages.E18);
        signer[_signer] = _value;
        emit UpdateSigner(_signer, _value);
    }

   /**
     * @dev Updates the soft cap value.
     * @param _value New soft cap value.
     * require Soft cap must not have been reached already.
     * Emits an event if the new soft cap is reached.
    */
    function updateSoftCap(uint256 _value) external onlyAdminOrOwner {
        require(!isSoftCapReached, ErrorMessages.E19);
        softCap = _value;
        if (currentSupply <= totalSupply() - _value) {
            isSoftCapReached = true;
            emit SoftCapReachecd(true);
        }
        emit UpdateSoftCap(_value);
    }

    /**
     * @dev Updates the campaign end time.
     * @param _campaignEndTime New end time for the campaign.
     * require The new end time must be after the campaign start time.
    */
    function updateCampaignEndTime(uint256 _campaignEndTime) external onlyAdminOrOwner {
        require(_campaignEndTime > campaignStartTime, ErrorMessages.E20);
        campaignEndTime = _campaignEndTime;
        emit CampaignEndTime(_campaignEndTime);
    }

    /**
     * @dev Updates the token value increase percentage.
     * @param _percentage New percentage value.
    */

    function updatePercentage(uint256 _percentage) external onlyAdminOrOwner {
        percentage = _percentage;
        emit TokenValueIncreasePercentage(_percentage);
    }

    /**
     * @dev Updates the withdrawal status.
     * @param _value Boolean indicating if withdrawals are allowed.
    */
    function updateWithdrawalStatus(bool _value) external onlyAdminOrOwner{
        withdrawalAllowed = _value;
        emit UpdateWithdrawlStatus(_value);
    }

    /**
     * @dev Increases the base token price if the soft cap is reached and the campaign has ended.
     * @param _isSoftCapReached Indicates if the soft cap has been reached.
     * @return The updated base token price.
    */
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

    /**
     * @dev Handles token purchase, including validation and state updates.
     * @param _tokenAmount Amount of tokens to purchase.
     * @param _investorAddress Address of the investor.
    */
    function _buyTokens(uint256 _tokenAmount, address _investorAddress) internal {
        require(
            liquidityTokenContract.allowance(_investorAddress, address(this)) >=
                _tokenAmount &&
                liquidityTokenContract.balanceOf(_investorAddress) >= _tokenAmount,
            ErrorMessages.E15
        );
        uint tokenPrice = increseBaseTokenValue(isSoftCapReached);
        uint256 tokensToPurchase = (_tokenAmount * 10 ** liquidityTokenContract.decimals()) /
            tokenPrice;
         require(
            tokensToPurchase <= hardCap,
           ErrorMessages.E21
        );
        require(
            balanceOf(address(this)) >= tokensToPurchase,
            ErrorMessages.E21
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

    /**
     * @dev Validates the provided data and signature.
     * @param _signature The signature to verify.
     * @param _investorAddress The address of the investor.
     * @param _tokenAmount The amount of tokens involved.
     * @param _networkFee The network fee amount.
     * @param _nonce The nonce for replay protection.
     */
    function _validateData(bytes memory _signature, address _investorAddress, uint256 _tokenAmount, uint256 _networkFee,  uint256 _nonce) internal view {
        require(_nonce == nonces[_investorAddress], ErrorMessages.E23);
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
        require(investorAddress == _investorAddress, ErrorMessages.E24);
    }

    /**
     * @dev Validates the investor by recovering the address from the signed message.
     * @param _message The message hash.
     * @param signature The signature to verify.
     * @return The address that signed the message.
    */
    function _validateInvestor(bytes32 _message, bytes memory signature)
        internal 
        pure
        returns (address)
    {
        _message = MessageHashUtils.toEthSignedMessageHash(_message);
        return ECDSA.recover(_message, signature);
    }

    /** 
     *  @notice Updates the wallet address for collecting network fees.
     * @param _feeWallet New network fee wallet address.
     * @dev Requires the caller to be an admin or owner.
     * @dev Emits an `UpdateFeeWallet` event.
    */
    function updateNetworkFeeWallet(address _feeWallet) external onlyAdminOrOwner{
        networkFeeWallet = _feeWallet;
        emit UpdateFeeWallet(_feeWallet);
    }

    /**
     * @dev Validates token transaction by checking balance and profit pool.
     * @param _investorAddress Address of the investor.
     * @param _tokenAmount Amount of tokens to validate.
     * @return tokens The valid token amount.
    */
    function _validateTokenTransaction(address _investorAddress, uint256 _tokenAmount ) internal view returns(uint256) {
        require(profitPool > 0, ErrorMessages.E25);

        require(
            balanceOf(_investorAddress) >= _tokenAmount,
        ErrorMessages.E26
        );

        uint256 tokens = (_tokenAmount * baseTokenPrice) /
            10 ** liquidityTokenContract.decimals();
        require(profitPool >= tokens, ErrorMessages.E27);
        return tokens;
    }

    /**
     * @dev Transfers the network fee to the fee wallet.
     * @param _networkFee Amount of fee to transfer.
     */
    function handleNetworkFee(
        uint256 _networkFee
    ) internal {
            SafeERC20.safeTransfer(liquidityTokenContract, networkFeeWallet, _networkFee);
        
    }

}
