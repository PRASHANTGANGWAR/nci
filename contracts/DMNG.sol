// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IERC20Extended.sol";

contract NCIContract is ERC20, Ownable {
    using SafeERC20 for IERC20Extended;

    uint8 private customDecimals;
    uint256 public baseTokenPrice;
    uint256 public currentSupply;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public investorPool;
    uint256 public profitPool;
    uint256 public campaignStartTime;
    uint256 public campaignEndTime;
    uint256 public totalRaised;
    uint256 public tokenInCirculation;
    uint256 public percentage = 10;
    bool public softCapReached;

    IERC20Extended public liquidityTokenContract;

    mapping(address => bool) public admin;

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
    event WithdrawnInvestor(
        address indexed investor,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount,
        uint256 blockTimestamp,
        uint256 newProfitPool
    );
    event WithdrawAdminOwner(
        address indexed ownerAdminAddress,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event UpdateAdmin(address indexed adminAddress, bool value);
    event AddLiquidity(
        address indexed ownerAdminAddress,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event UpdateSoftCap(uint256 value);
    event SoftCapReachecd(bool value);
    event CampaignEndTime(uint256 _campaignEndTime);
    event ChangePercent(uint256 _percentage);

    constructor(
        string memory _tokenName,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _campaignEndTime,
        uint8 _customDecimals,
        address _liquidityTokenContract,
        address _initialOwner,
        address _admin
    ) Ownable(_initialOwner) ERC20(_tokenName, _symbol) {
        require(
            _campaignEndTime > 0,
            "Campaign duration must be greater than zero"
        );
        require(_softCap < _hardCap, "Soft cap must be less than hard cap");

        _mint(address(this), _initialSupply);

        currentSupply = _initialSupply;
        softCap = _softCap;
        hardCap = _hardCap;

        softCapReached = false;
        liquidityTokenContract = IERC20Extended(_liquidityTokenContract);
        baseTokenPrice =
            5 *
            (10**IERC20Extended(_liquidityTokenContract).decimals());
        customDecimals = _customDecimals;
        campaignStartTime = block.number;
        campaignEndTime = _campaignEndTime;
        admin[_admin] = true;
    }

    modifier campaignComplete() {
        require(
            block.number >= campaignEndTime,
            "Campaign has not been completed"
        );
        _;
    }

    modifier softCapReachedOnly() {
        require(softCapReached, "Soft cap is not reached");
        _;
    }

    modifier hardCapNotReachedOnly() {
        require(totalRaised < hardCap, "Cannot buy tokens: Hard cap reached.");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(admin[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }


    modifier withdrawEnabledOrNot() {
        if (block.number > campaignEndTime) {
            require(!softCapReached, "Withdraw is disabled");
        }
        _;
    }

    // Function to purchase tokens during the campaign
    function buyTokens(uint256 _tokenValue)
        external
        hardCapNotReachedOnly
    {
        require(_tokenValue > 0, "The amount must be greater than zero.");
        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _tokenValue &&
                liquidityTokenContract.balanceOf(msg.sender) >= _tokenValue,
            "Insufficient allowance or balance"
        );

        uint256 tokensToPurchase = (_tokenValue * 10**customDecimals) /
            baseTokenPrice;
         require(
            tokensToPurchase <= hardCap,
            "Purchase denied. The requested amount exceeds the available tokens in the pool. Please try with a lower amount."
        );
        require(
            balanceOf(address(this)) >= tokensToPurchase,
            "Not enough tokens available"
        );

        liquidityTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            _tokenValue
        );
        investorPool += _tokenValue;
        currentSupply -= tokensToPurchase;
        totalRaised += tokensToPurchase;
        tokenInCirculation += tokensToPurchase;

        _transfer(address(this), msg.sender, tokensToPurchase);
        if (!softCapReached && currentSupply <= totalSupply() - softCap) {
            softCapReached = true;
            emit SoftCapReachecd(true);
        }
        emit TokensPurchased(
            msg.sender,
            _tokenValue,
            tokensToPurchase,
            baseTokenPrice,
            block.timestamp
        );
       
    
    }

    // Function to sell tokens after the campaign is completed
    function sellTokens(uint256 _tokenValue)
        external
        campaignComplete
        softCapReachedOnly
    {
        _withdraw(_tokenValue);
    }

    // Admin or Owner withdraws funds in investor pool
    function withdrawAdminOwner(uint256 _tokenValue)
        external
        onlyAdminOrOwner
        softCapReachedOnly
    {
        require(investorPool >= _tokenValue, "Insufficient liquidity in pool");

        liquidityTokenContract.safeTransfer(msg.sender, _tokenValue);
        investorPool -= _tokenValue;

        emit WithdrawAdminOwner(msg.sender, _tokenValue, block.timestamp);
    }


    // Admin or Owner withdraws funds in profit pool
    function withdrawInProfitPool() external onlyAdminOrOwner {
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

        emit WithdrawAdminOwner(msg.sender, remainingToken, block.timestamp);
    }

    // Add profits to the contract, updating the base token price
    function addProfit(uint256 _profitAmount)
        external
        onlyAdminOrOwner
        softCapReachedOnly
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
        softCapReachedOnly
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
    function withdrawInvestment(uint256 _tokenValue)
        external
        withdrawEnabledOrNot
    {
        _withdraw(_tokenValue);
    }

    // Internal withdraw function
    function _withdraw(uint256 _tokenValue) internal {
        require(profitPool > 0, "Please wait for the profit to be added to pool");

        require(
            _tokenValue > 0 && balanceOf(msg.sender) >= _tokenValue,
            "Insufficient balance"
        );

        uint256 tokens = (_tokenValue * baseTokenPrice) /
            10**liquidityTokenContract.decimals();
        require(profitPool >= tokens, "Insufficient tokens in pool. Please try with an amount less than");

        liquidityTokenContract.safeTransfer(msg.sender, tokens);

        // burn dmng token
        _burn(msg.sender, _tokenValue);
        profitPool -= tokens;
        tokenInCirculation -= _tokenValue;

        emit WithdrawnInvestor(
            msg.sender,
            _tokenValue,
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
        if(newTokenPrice >= _baseTokenPrice + _baseTokenPrice * percentage / 1000){
            return _baseTokenPrice * percentage / 1000;
        }
        return newTokenPrice;
    }

    // Override the decimals function to return custom decimals
    function decimals() public view virtual override returns (uint8) {
        return customDecimals;
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


  // Update soft status
    function updateSoftCap(uint256 _value) external onlyAdminOrOwner {
        require(!softCapReached, "Soft cap already reached");
        softCap = _value;
        if (currentSupply <= totalSupply() - _value) {
            softCapReached = true;
            emit SoftCapReachecd(true);
        }
        emit UpdateSoftCap(_value);
    }

    //Update campaign end time
    function updateCampaignEndTime(uint256 _campaignEndTime) external onlyAdminOrOwner {
        require(_campaignEndTime > block.number, "Please provide the end time greater than current block numnber");
        campaignEndTime = _campaignEndTime;
        emit CampaignEndTime(_campaignEndTime);
    }

    function updatePercentage(uint256 _percentage) external onlyAdminOrOwner {
        percentage = _percentage;
        emit ChangePercent(_percentage);
    }


}
